"""
backend/tests/conftest.py
Shared pytest configuration for OmniShelf backend tests.
"""
import os
import sys
from pathlib import Path

# Ensure all Lambda handlers are importable during test runs
LAMBDA_ROOT = Path(__file__).resolve().parent.parent / "lambdas"
for service in ("inventoryService", "alertService", "ocrService"):
    p = str(LAMBDA_ROOT / service)
    if p not in sys.path:
        sys.path.insert(0, p)

# Prevent boto3 from picking up real AWS credentials during tests
os.environ.setdefault("AWS_ACCESS_KEY_ID",     "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("AWS_DEFAULT_REGION",    "us-east-1")
