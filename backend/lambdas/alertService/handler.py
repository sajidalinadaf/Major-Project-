"""
alertService/handler.py
OmniShelf -- Scheduled Expiry Alert Lambda
------------------------------------------
Triggered daily by EventBridge (CloudWatch Events).
Scans DynamoDB for items expiring within ALERT_THRESHOLD_DAYS (default 7)
and sends a consolidated SNS notification to the store manager.

Environment variables:
  INVENTORY_TABLE      -- DynamoDB table name  (default: OmniShelfInventory)
  SNS_TOPIC_ARN        -- ARN of the SNS topic for manager alerts
  ALERT_THRESHOLD_DAYS -- Days before expiry to alert (default: 7)
  STORE_NAME           -- Human-readable store name for notification subject

Design note: all AWS clients and config values are resolved lazily inside the
handler() entry-point so that unit tests can patch os.environ and moto can
intercept calls correctly, without module-level bindings to real AWS endpoints.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# ---------------------------------------------------------------------------
# Internal helpers (accept clients / config as parameters for testability)
# ---------------------------------------------------------------------------

class _DecimalEncoder(json.JSONEncoder):
    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


def _scan_expiring_items(table, today: date, threshold_date: date) -> list[dict]:
    """
    Scan DynamoDB for:
      - Items with expiryDate between today and threshold_date (inclusive), qty > 0
      - Items with expiryDate before today (already expired), qty > 0
    """
    today_str     = today.isoformat()
    threshold_str = threshold_date.isoformat()
    expiring: list[dict] = []

    # -- near-expiry items ---------------------------------------------------
    try:
        resp = table.scan(
            FilterExpression=(
                Attr("expiryDate").between(today_str, threshold_str)
                & Attr("quantity").gt(0)
            )
        )
        expiring.extend(resp.get("Items", []))
        while "LastEvaluatedKey" in resp:
            resp = table.scan(
                FilterExpression=(
                    Attr("expiryDate").between(today_str, threshold_str)
                    & Attr("quantity").gt(0)
                ),
                ExclusiveStartKey=resp["LastEvaluatedKey"],
            )
            expiring.extend(resp.get("Items", []))
    except ClientError as exc:
        logger.error("DynamoDB scan (expiring) error: %s", exc)
        raise

    # -- already-expired items -----------------------------------------------
    try:
        resp2 = table.scan(
            FilterExpression=(
                Attr("expiryDate").lt(today_str)
                & Attr("quantity").gt(0)
            )
        )
        expiring.extend(resp2.get("Items", []))
        while "LastEvaluatedKey" in resp2:
            resp2 = table.scan(
                FilterExpression=(
                    Attr("expiryDate").lt(today_str)
                    & Attr("quantity").gt(0)
                ),
                ExclusiveStartKey=resp2["LastEvaluatedKey"],
            )
            expiring.extend(resp2.get("Items", []))
    except ClientError as exc:
        logger.warning("Could not scan expired items: %s", exc)

    expiring.sort(key=lambda x: x.get("expiryDate", "9999-99-99"))
    return expiring


def _build_email_message(items: list[dict], today: date, threshold_date: date,
                          threshold_days: int, store_name: str) -> str:
    today_s     = today.isoformat()
    thresh_s    = threshold_date.isoformat()
    expired     = [i for i in items if i.get("expiryDate", "") < today_s]
    expiring    = [i for i in items if today_s <= i.get("expiryDate", "") <= thresh_s]

    lines = [
        f"OmniShelf Daily Expiry Alert -- {store_name}",
        f"Report Date: {today_s}",
        "=" * 60,
        "",
    ]

    if expired:
        lines.append(f"ALREADY EXPIRED ({len(expired)} item(s)):")
        lines.append("-" * 40)
        for item in expired:
            lines.append(
                f"  * {item.get('productName', 'Unknown')} "
                f"[Batch: {item.get('batchNumber', 'N/A')}] "
                f"[SKU: {item.get('sku', 'N/A')}]\n"
                f"    Expired: {item.get('expiryDate', '?')} | "
                f"Stock: {item.get('quantity', 0)} units"
            )
        lines.append("")

    if expiring:
        lines.append(f"EXPIRING WITHIN {threshold_days} DAYS ({len(expiring)} item(s)):")
        lines.append("-" * 40)
        for item in expiring:
            exp = item.get("expiryDate", "Unknown")
            days_left = (date.fromisoformat(exp) - today).days if exp != "Unknown" else "?"
            lines.append(
                f"  * {item.get('productName', 'Unknown')} "
                f"[Batch: {item.get('batchNumber', 'N/A')}] "
                f"[SKU: {item.get('sku', 'N/A')}]\n"
                f"    Expires: {exp} ({days_left} day(s) remaining) | "
                f"Stock: {item.get('quantity', 0)} units"
            )
        lines.append("")

    lines += [
        "=" * 60,
        "ACTION REQUIRED:",
        "  1. Review expired items and remove from shelves immediately.",
        "  2. Consider markdowns or promotions for near-expiry items.",
        "  3. Log dispatches in the OmniShelf app to update stock counts.",
        "",
        "This is an automated alert from OmniShelf. Do not reply.",
    ]
    return "\n".join(lines)


def _publish_sns_alert(sns_client, topic_arn: str, subject: str,
                        message: str, store_name: str) -> str:
    """Publish alert to SNS. Raises ValueError if topic_arn is blank."""
    if not topic_arn:
        raise ValueError("SNS_TOPIC_ARN environment variable is not set")
    resp = sns_client.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message,
        MessageAttributes={
            "alert_type": {"DataType": "String", "StringValue": "EXPIRY_WARNING"},
            "store":      {"DataType": "String", "StringValue": store_name},
        },
    )
    return resp["MessageId"]


# ---------------------------------------------------------------------------
# Lambda entry point
# ---------------------------------------------------------------------------

def handler(event: dict, context: Any) -> dict:  # noqa: ANN401
    """
    EventBridge-triggered daily Lambda.
    All config is read from os.environ at call time (lazy) for testability.
    Returns a plain dict summary (not API Gateway format -- this is not HTTP).
    """
    # -- resolve config from env at call time --------------------------------
    table_name     = os.environ.get("INVENTORY_TABLE", "OmniShelfInventory")
    sns_topic_arn  = os.environ.get("SNS_TOPIC_ARN", "")
    threshold_days = int(os.environ.get("ALERT_THRESHOLD_DAYS", "7"))
    store_name     = os.environ.get("STORE_NAME", "OmniShelf Store")

    # -- lazy AWS clients ----------------------------------------------------
    dynamodb_res = boto3.resource("dynamodb")
    table        = dynamodb_res.Table(table_name)
    sns_client   = boto3.client("sns")

    logger.info("Alert service triggered. threshold=%d days, table=%s", threshold_days, table_name)

    today          = date.today()
    threshold_date = today + timedelta(days=threshold_days)

    # -- scan ----------------------------------------------------------------
    try:
        items = _scan_expiring_items(table, today, threshold_date)
    except ClientError as exc:
        logger.error("Failed to scan inventory: %s", exc)
        return {"status": "error", "message": str(exc)}

    total = len(items)
    logger.info("Found %d item(s) requiring attention", total)

    if total == 0:
        return {
            "status":  "ok",
            "message": "No items expiring within the alert window.",
            "date":    today.isoformat(),
        }

    # -- build + publish notification ----------------------------------------
    today_s    = today.isoformat()
    thresh_s   = threshold_date.isoformat()
    subject    = (
        f"[OmniShelf] {total} Item(s) Require Attention "
        f"-- {store_name} -- {today_s}"
    )
    message = _build_email_message(items, today, threshold_date, threshold_days, store_name)

    try:
        message_id = _publish_sns_alert(sns_client, sns_topic_arn, subject, message, store_name)
        logger.info("SNS alert published. MessageId: %s", message_id)
    except (ClientError, ValueError) as exc:
        logger.error("Failed to publish SNS alert: %s", exc)
        return {"status": "error", "message": str(exc), "itemsFound": total}

    return {
        "status":        "ok",
        "alertsSent":    1,
        "itemsFound":    total,
        "snsMessageId":  message_id,
        "date":          today_s,
        "thresholdDays": threshold_days,
        "summary": {
            "expired":  len([i for i in items if i.get("expiryDate", "") < today_s]),
            "expiring": len([i for i in items if today_s <= i.get("expiryDate", "") <= thresh_s]),
        },
    }
