"""
inventoryService/handler.py
OmniShelf -- Inventory CRUD Lambda
-----------------------------------
Handles:
  GET  /inventory  -- List all items sorted by FEFO (earliest expiry first)
  POST /inventory  -- Create or upsert a batch record
  POST /dispatch   -- Atomically decrement stock quantity

DynamoDB table: OmniShelfInventory
  PK: id  (batchNumber#sku)
  GSI: ExpiryIndex  (expiryDate, for FEFO scans)

Design note: boto3 clients are resolved lazily inside each function so that
unit tests can patch os.environ and moto can intercept calls correctly,
without needing module-level client objects that bind to real AWS endpoints
at import time.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

# -- Logging ------------------------------------------------------------------
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

CORS_HEADERS = {
    "Access-Control-Allow-Origin":  "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT,DELETE",
    "Content-Type":                 "application/json",
}


# -- Lazy client helpers ------------------------------------------------------

def _get_table(table_env_var: str, default: str):
    """Return a DynamoDB Table object resolved from the current env at call time."""
    table_name = os.environ.get(table_env_var, default)
    dynamodb = boto3.resource("dynamodb")
    return dynamodb.Table(table_name)


# -- Generic helpers ----------------------------------------------------------

class _DecimalEncoder(json.JSONEncoder):
    """Serialise DynamoDB Decimal to int/float, and any remaining unknown
    types to their string representation."""
    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        try:
            return super().default(obj)
        except TypeError:
            return str(obj)


def _response(status: int, body: Any) -> dict:
    """Build a standard API Gateway proxy response dict."""
    return {
        "statusCode": status,
        "headers":    CORS_HEADERS,
        "body":       json.dumps(body, cls=_DecimalEncoder),
    }


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _build_id(batch_number: str, sku: str) -> str:
    return f"{batch_number}#{sku}"


def _write_audit(action: str, item_id: str, delta: int, actor: str = "system") -> None:
    """Write an immutable audit record (fire-and-forget, non-fatal on failure)."""
    try:
        audit = _get_table("AUDIT_TABLE", "OmniShelfAudit")
        audit.put_item(Item={
            "auditId":   f"{action}#{item_id}#{_now_iso()}",
            "action":    action,
            "itemId":    item_id,
            "delta":     delta,
            "actor":     actor,
            "timestamp": _now_iso(),
        })
    except ClientError as exc:
        logger.warning("Audit write failed (non-fatal): %s", exc)


# -- Route handlers -----------------------------------------------------------

def _get_inventory(event: dict) -> dict:
    """
    GET /inventory
    Returns all inventory items sorted by expiryDate ascending (FEFO).
    Supports optional query param: ?sku=AMB-500 to filter by SKU.
    """
    table = _get_table("INVENTORY_TABLE", "OmniShelfInventory")

    params = event.get("queryStringParameters") or {}
    sku_filter = params.get("sku")

    try:
        if sku_filter:
            resp = table.scan(FilterExpression=Attr("sku").eq(sku_filter))
        else:
            resp = table.scan()
    except ClientError as exc:
        logger.error("DynamoDB scan error: %s", exc)
        return _response(500, {"error": "Failed to retrieve inventory"})

    items = resp.get("Items", [])

    # Paginate for large tables
    while "LastEvaluatedKey" in resp:
        try:
            resp = table.scan(ExclusiveStartKey=resp["LastEvaluatedKey"])
            items += resp.get("Items", [])
        except ClientError as exc:
            logger.error("DynamoDB pagination error: %s", exc)
            break

    # FEFO sort: earliest expiryDate first; items without date go to end
    items.sort(key=lambda i: i.get("expiryDate") or "9999-99-99")

    return _response(200, {"items": items, "count": len(items)})


def _post_inventory(body: dict) -> dict:
    """
    POST /inventory
    Create or update a batch record (upsert by batchNumber#sku PK).
    Required fields: productName, sku, batchNumber, expiryDate, quantity
    """
    required = ["productName", "sku", "batchNumber", "expiryDate", "quantity"]
    missing  = [f for f in required if not body.get(f)]
    if missing:
        return _response(400, {"error": f"Missing required fields: {missing}"})

    table = _get_table("INVENTORY_TABLE", "OmniShelfInventory")

    sku          = str(body["sku"]).strip()
    batch_number = str(body["batchNumber"]).strip()
    item_id      = _build_id(batch_number, sku)
    now          = _now_iso()

    item = {
        "id":               item_id,
        "productName":      str(body["productName"]).strip(),
        "sku":              sku,
        "batchNumber":      batch_number,
        "expiryDate":       str(body["expiryDate"]).strip(),
        "quantity":         int(body["quantity"]),
        "storageGuideline": str(body.get("storageGuideline", "")).strip(),
        "updatedAt":        now,
    }

    # Preserve createdAt on upsert
    try:
        existing = table.get_item(Key={"id": item_id}).get("Item")
        item["createdAt"] = existing["createdAt"] if existing else now
    except ClientError:
        item["createdAt"] = now

    try:
        table.put_item(Item=item)
    except ClientError as exc:
        logger.error("DynamoDB put_item error: %s", exc)
        return _response(500, {"error": "Failed to save inventory record"})

    _write_audit("UPSERT", item_id, item["quantity"])
    logger.info("Upserted item: %s", item_id)
    return _response(201, item)


def _post_dispatch(body: dict) -> dict:
    """
    POST /dispatch
    Atomically decrements the stock quantity for a given batch.
    Required fields: batchNumber, sku, quantity (units to dispatch)
    Returns 409 if insufficient stock, 404 if batch not found.
    """
    required = ["batchNumber", "sku", "quantity"]
    missing  = [f for f in required if f not in body]
    if missing:
        return _response(400, {"error": f"Missing required fields: {missing}"})

    table = _get_table("INVENTORY_TABLE", "OmniShelfInventory")

    sku           = str(body["sku"]).strip()
    batch_number  = str(body["batchNumber"]).strip()
    item_id       = _build_id(batch_number, sku)
    qty_to_remove = int(body["quantity"])

    if qty_to_remove <= 0:
        return _response(400, {"error": "quantity must be a positive integer"})

    try:
        resp = table.update_item(
            Key={"id": item_id},
            UpdateExpression="SET quantity = quantity - :dec, updatedAt = :now",
            ConditionExpression="quantity >= :dec AND attribute_exists(id)",
            ExpressionAttributeValues={
                ":dec": qty_to_remove,
                ":now": _now_iso(),
            },
            ReturnValues="ALL_NEW",
        )
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code == "ConditionalCheckFailedException":
            existing = table.get_item(Key={"id": item_id}).get("Item")
            if not existing:
                return _response(404, {"error": f"Batch {item_id} not found"})
            return _response(409, {
                "error":           "Insufficient stock",
                "availableStock":  int(existing.get("quantity", 0)),
                "requestedAmount": qty_to_remove,
            })
        logger.error("DynamoDB update_item error: %s", exc)
        return _response(500, {"error": "Dispatch operation failed"})

    updated_item = resp.get("Attributes", {})
    _write_audit("DISPATCH", item_id, -qty_to_remove, body.get("actor", "system"))
    # Convert Decimal to int so JSON serialisation is deterministic
    remaining = updated_item.get("quantity")
    if isinstance(remaining, Decimal):
        remaining = int(remaining)
    logger.info(
        "Dispatched %d units from %s. Remaining: %s",
        qty_to_remove, item_id, remaining,
    )
    return _response(200, {
        "message":        f"Dispatched {qty_to_remove} units successfully",
        "batchNumber":    batch_number,
        "sku":            sku,
        "remainingStock": remaining,
    })


# -- Lambda entry point -------------------------------------------------------

def handler(event: dict, context: Any) -> dict:  # noqa: ANN401
    """Route based on httpMethod + resource/path."""
    http_method = (event.get("httpMethod") or "").upper()
    resource    = event.get("resource") or event.get("path") or ""

    logger.info("Request: %s %s", http_method, resource)

    # CORS preflight -- always 200 with headers
    if http_method == "OPTIONS":
        return _response(200, {"message": "ok"})

    # Parse body for POST requests
    body: dict = {}
    if http_method == "POST":
        try:
            raw_body = event.get("body") or "{}"
            body = json.loads(raw_body) if isinstance(raw_body, str) else (raw_body or {})
        except (json.JSONDecodeError, ValueError) as exc:
            return _response(400, {"error": f"Invalid JSON body: {exc}"})

    # Route dispatch
    if http_method == "GET" and "/inventory" in resource:
        return _get_inventory(event)

    if http_method == "POST" and "/inventory" in resource:
        return _post_inventory(body)

    if http_method == "POST" and "/dispatch" in resource:
        return _post_dispatch(body)

    return _response(404, {"error": f"Route not found: {http_method} {resource}"})
