"""
ocrService/handler.py
OmniShelf — OCR + AI Extraction Lambda
---------------------------------------
Accepts a base64-encoded product packaging image from the mobile app,
runs AWS Textract to extract raw text, then feeds that text into
Amazon Bedrock (Claude 3 Haiku) to produce structured inventory data.

Expected API Gateway event body (JSON):
{
    "image": "<base64-encoded JPEG/PNG>",
    "contentType": "image/jpeg"          # optional, defaults to image/jpeg
}

Response:
{
    "productName":       "Amul Butter 500g",
    "sku":               "AMB-500",
    "batchNumber":       "BATCH-2024-0312",
    "expiryDate":        "2025-03-12",    # ISO-8601 YYYY-MM-DD
    "storageGuideline":  "Store below 4C"
}
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
from datetime import datetime
from typing import Any

import boto3
from botocore.exceptions import ClientError

# ── Logging ───────────────────────────────────────────────────────────────────
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ── AWS clients ───────────────────────────────────────────────────────────────
textract = boto3.client("textract")
bedrock  = boto3.client("bedrock-runtime", region_name=os.environ.get("AWS_REGION", "us-east-1"))

# ── Constants ─────────────────────────────────────────────────────────────────
BEDROCK_MODEL_ID  = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
FALLBACK_MODEL_ID = os.environ.get("FALLBACK_MODEL_ID", "amazon.titan-text-express-v1")
MAX_TOKENS        = int(os.environ.get("BEDROCK_MAX_TOKENS", "512"))

CORS_HEADERS = {
    "Access-Control-Allow-Origin":  "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,POST",
    "Content-Type":                 "application/json",
}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _response(status: int, body: Any) -> dict:
    return {
        "statusCode": status,
        "headers":    CORS_HEADERS,
        "body":       json.dumps(body, default=str),
    }


def _extract_text_with_textract(image_bytes: bytes) -> str:
    """Run Textract DetectDocumentText and concatenate all LINE blocks."""
    try:
        resp = textract.detect_document_text(
            Document={"Bytes": image_bytes}
        )
    except ClientError as exc:
        logger.error("Textract error: %s", exc)
        raise RuntimeError(f"Textract failed: {exc.response['Error']['Code']}") from exc

    lines: list[str] = []
    for block in resp.get("Blocks", []):
        if block.get("BlockType") == "LINE":
            lines.append(block.get("Text", ""))

    raw_text = "\n".join(lines)
    logger.info("Textract extracted %d lines", len(lines))
    return raw_text


def _build_extraction_prompt(raw_text: str) -> str:
    return f"""You are an expert at reading product packaging labels.
Below is text extracted from a product label via OCR.

<label_text>
{raw_text}
</label_text>

Extract the following fields and return ONLY valid JSON (no markdown, no explanation):
{{
  "productName":      "<full product name including brand and variant>",
  "sku":              "<Stock Keeping Unit / product code, or null if not found>",
  "batchNumber":      "<batch or lot number, or null if not found>",
  "expiryDate":       "<expiry date in YYYY-MM-DD format, or null if not found>",
  "storageGuideline": "<storage instructions, e.g. 'Store below 4C', or empty string>"
}}

Rules:
- expiryDate MUST be ISO-8601 YYYY-MM-DD. Convert "Mar 2025" → "2025-03-01", "12/03/25" → "2025-03-12".
- If a field is genuinely absent from the label, use null (not "N/A").
- productName must never be null; infer from context if needed.
"""


def _call_claude(prompt: str) -> dict:
    """Call Claude 3 Haiku via Bedrock and parse JSON response."""
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens":        MAX_TOKENS,
        "messages": [
            {"role": "user", "content": prompt}
        ],
    }
    try:
        resp = bedrock.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=json.dumps(payload),
            contentType="application/json",
            accept="application/json",
        )
        body = json.loads(resp["body"].read())
        text = body["content"][0]["text"]
        return _parse_json_response(text)
    except (ClientError, KeyError, json.JSONDecodeError) as exc:
        logger.warning("Claude failed (%s), falling back to Titan", exc)
        return _call_titan(prompt)


def _call_titan(prompt: str) -> dict:
    """Fallback: Amazon Titan Text Express."""
    payload = {
        "inputText":        prompt,
        "textGenerationConfig": {
            "maxTokenCount": MAX_TOKENS,
            "temperature":   0.0,
        },
    }
    resp = bedrock.invoke_model(
        modelId=FALLBACK_MODEL_ID,
        body=json.dumps(payload),
        contentType="application/json",
        accept="application/json",
    )
    body = json.loads(resp["body"].read())
    text = body["results"][0]["outputText"]
    return _parse_json_response(text)


def _parse_json_response(text: str) -> dict:
    """Extract and parse the JSON block from model output."""
    # Strip any markdown code fences
    text = re.sub(r"```(?:json)?", "", text).strip()
    # Find the first {...} block
    match = re.search(r"\{[\s\S]*\}", text)
    if not match:
        raise ValueError(f"No JSON object found in model response: {text[:200]}")
    return json.loads(match.group())


def _validate_and_normalise(data: dict) -> dict:
    """Ensure required fields exist and normalise expiry date."""
    product_name = data.get("productName") or "Unknown Product"
    sku          = data.get("sku")
    batch_number = data.get("batchNumber")
    expiry_raw   = data.get("expiryDate")
    storage      = data.get("storageGuideline") or ""

    # Normalise expiry date
    expiry_iso: str | None = None
    if expiry_raw:
        # Already YYYY-MM-DD?
        if re.match(r"^\d{4}-\d{2}-\d{2}$", str(expiry_raw)):
            expiry_iso = expiry_raw
        else:
            # Try common patterns
            for fmt in ("%d/%m/%Y", "%m/%d/%Y", "%d-%m-%Y", "%b %Y", "%B %Y", "%Y/%m/%d"):
                try:
                    dt = datetime.strptime(str(expiry_raw), fmt)
                    expiry_iso = dt.strftime("%Y-%m-%d")
                    break
                except ValueError:
                    continue

    return {
        "productName":      product_name,
        "sku":              sku,
        "batchNumber":      batch_number,
        "expiryDate":       expiry_iso,
        "storageGuideline": storage,
    }


# ── Handler ───────────────────────────────────────────────────────────────────

def handler(event: dict, context: Any) -> dict:  # noqa: ANN401
    """Lambda entry point."""
    # Handle CORS preflight
    if event.get("httpMethod") == "OPTIONS":
        return _response(200, {"message": "ok"})

    # Parse body
    try:
        body_raw = event.get("body", "{}")
        if event.get("isBase64Encoded"):
            body_raw = base64.b64decode(body_raw).decode("utf-8")
        body = json.loads(body_raw) if isinstance(body_raw, str) else body_raw
    except (json.JSONDecodeError, ValueError) as exc:
        return _response(400, {"error": f"Invalid request body: {exc}"})

    image_b64 = body.get("image")
    if not image_b64:
        return _response(400, {"error": "Missing required field: image (base64)"})

    # Decode image
    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception as exc:  # noqa: BLE001
        return _response(400, {"error": f"Failed to decode image: {exc}"})

    # Step 1: Textract OCR
    try:
        raw_text = _extract_text_with_textract(image_bytes)
    except RuntimeError as exc:
        return _response(502, {"error": str(exc)})

    if not raw_text.strip():
        return _response(422, {"error": "No text detected in the provided image."})

    # Step 2: Bedrock AI extraction
    try:
        prompt   = _build_extraction_prompt(raw_text)
        raw_data = _call_claude(prompt)
        result   = _validate_and_normalise(raw_data)
    except Exception as exc:  # noqa: BLE001
        logger.error("Bedrock extraction failed: %s", exc)
        return _response(502, {"error": f"AI extraction failed: {exc}"})

    logger.info("Extraction result: %s", result)
    return _response(200, result)
