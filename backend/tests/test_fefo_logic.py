"""
backend/tests/test_fefo_logic.py
OmniShelf -- Pytest suite: FEFO sorting, alert thresholds, dispatch logic.

Run from the project root:
    pip install pytest "moto[dynamodb,sns]" boto3
    pytest backend/tests/test_fefo_logic.py -v
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import types
import unittest.mock as mock
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

# ---------------------------------------------------------------------------
# Absolute paths to the two handler files we test
# ---------------------------------------------------------------------------
LAMBDA_ROOT   = Path(__file__).resolve().parent.parent / "lambdas"
INV_HANDLER   = LAMBDA_ROOT / "inventoryService" / "handler.py"
ALERT_HANDLER = LAMBDA_ROOT / "alertService"     / "handler.py"

assert INV_HANDLER.exists(),   f"Missing: {INV_HANDLER}"
assert ALERT_HANDLER.exists(), f"Missing: {ALERT_HANDLER}"

# ---------------------------------------------------------------------------
# Date constants (computed once at collection time)
# ---------------------------------------------------------------------------
REGION         = "us-east-1"
TABLE_NAME     = "OmniShelfInventory-test"
AUDIT_TABLE    = "OmniShelfAudit-test"
SNS_TOPIC_NAME = "OmniShelfExpiryAlerts-test"
ALERT_EMAIL    = "test-manager@omnishelf.com"

TODAY      = date.today()
IN_3_DAYS  = (TODAY + timedelta(days=3)).isoformat()
IN_7_DAYS  = (TODAY + timedelta(days=7)).isoformat()
IN_10_DAYS = (TODAY + timedelta(days=10)).isoformat()
IN_30_DAYS = (TODAY + timedelta(days=30)).isoformat()
YESTERDAY  = (TODAY - timedelta(days=1)).isoformat()
LAST_WEEK  = (TODAY - timedelta(days=7)).isoformat()

INV_ENV = {
    "INVENTORY_TABLE": TABLE_NAME,
    "AUDIT_TABLE":     AUDIT_TABLE,
    "SNS_TOPIC_ARN":   "",
}
ALERT_ENV_BASE = {
    "INVENTORY_TABLE":      TABLE_NAME,
    "AUDIT_TABLE":          AUDIT_TABLE,
    "ALERT_THRESHOLD_DAYS": "7",
    "STORE_NAME":           "Test Store",
}

# ---------------------------------------------------------------------------
# Module loader helpers -- load by file path, independent of sys.path order
# ---------------------------------------------------------------------------

def _load_module(path: Path, module_name: str) -> types.ModuleType:
    """Load a Python file as a fresh module by absolute path."""
    spec = importlib.util.spec_from_file_location(module_name, str(path))
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _inv(event: dict, env_patch: dict) -> dict:
    """Call inventoryService handler with patched env. Requires active mock_aws."""
    with mock.patch.dict(os.environ, env_patch):
        mod = _load_module(INV_HANDLER, "inv_handler")
        return mod.handler(event, {})


def _alert(env_patch: dict, event: dict = None) -> dict:
    """Call alertService handler with patched env. Requires active mock_aws."""
    with mock.patch.dict(os.environ, env_patch):
        mod = _load_module(ALERT_HANDLER, "alert_handler")
        return mod.handler(event or {}, {})


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _fake_aws_creds():
    """Inject fake AWS credentials so boto3 never tries real AWS calls."""
    with mock.patch.dict(os.environ, {
        "AWS_ACCESS_KEY_ID":     "testing",
        "AWS_SECRET_ACCESS_KEY": "testing",
        "AWS_SECURITY_TOKEN":    "testing",
        "AWS_SESSION_TOKEN":     "testing",
        "AWS_DEFAULT_REGION":    REGION,
    }):
        yield


@pytest.fixture()
def dynamodb_tables():
    """
    Spin up mocked DynamoDB tables and keep the mock_aws context open
    for the duration of the test via generator yield.
    """
    with mock_aws():
        ddb = boto3.resource("dynamodb", region_name=REGION)

        inv = ddb.create_table(
            TableName=TABLE_NAME,
            BillingMode="PAY_PER_REQUEST",
            AttributeDefinitions=[
                {"AttributeName": "id",         "AttributeType": "S"},
                {"AttributeName": "expiryDate", "AttributeType": "S"},
                {"AttributeName": "sku",        "AttributeType": "S"},
            ],
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "ExpiryIndex",
                    "KeySchema": [{"AttributeName": "expiryDate", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                },
                {
                    "IndexName": "SkuIndex",
                    "KeySchema": [
                        {"AttributeName": "sku",        "KeyType": "HASH"},
                        {"AttributeName": "expiryDate", "KeyType": "RANGE"},
                    ],
                    "Projection": {"ProjectionType": "ALL"},
                },
            ],
        )

        aud = ddb.create_table(
            TableName=AUDIT_TABLE,
            BillingMode="PAY_PER_REQUEST",
            AttributeDefinitions=[
                {"AttributeName": "auditId",   "AttributeType": "S"},
                {"AttributeName": "timestamp", "AttributeType": "S"},
            ],
            KeySchema=[{"AttributeName": "auditId", "KeyType": "HASH"}],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "TimestampIndex",
                    "KeySchema": [{"AttributeName": "timestamp", "KeyType": "HASH"}],
                    "Projection": {"ProjectionType": "ALL"},
                }
            ],
        )

        yield {"inventory": inv, "audit": aud}


@pytest.fixture()
def sns_topic():
    """Mocked SNS topic -- yields its ARN inside an active mock_aws context."""
    with mock_aws():
        client = boto3.client("sns", region_name=REGION)
        arn    = client.create_topic(Name=SNS_TOPIC_NAME)["TopicArn"]
        client.subscribe(TopicArn=arn, Protocol="email", Endpoint=ALERT_EMAIL)
        yield arn


# ---------------------------------------------------------------------------
# Data helpers
# ---------------------------------------------------------------------------

def _make_item(sku, batch, expiry, quantity,
               product_name="Test Product", storage="Store cool"):
    now = datetime.now(timezone.utc).isoformat()
    return {
        "id":               f"{batch}#{sku}",
        "productName":      product_name,
        "sku":              sku,
        "batchNumber":      batch,
        "expiryDate":       expiry,
        "quantity":         quantity,
        "storageGuideline": storage,
        "createdAt":        now,
        "updatedAt":        now,
    }


def _seed(table, items: list) -> None:
    with table.batch_writer() as bw:
        for item in items:
            bw.put_item(Item=item)


# ===========================================================================
# Suite 1 -- FEFO Sorting
# ===========================================================================

class TestFefoSorting:
    """GET /inventory returns items sorted by expiryDate ascending (FEFO)."""

    @pytest.fixture(autouse=True)
    def _setup(self, dynamodb_tables):
        self.tables = dynamodb_tables

    FEFO_ITEMS = [
        _make_item("MILK-1L", "B-001", IN_30_DAYS, 10, "Whole Milk 1L"),
        _make_item("BREAD-W", "B-002", IN_10_DAYS, 20, "Wheat Bread 400g"),
        _make_item("PANEER",  "B-003", IN_3_DAYS,  5,  "Fresh Paneer 200g"),
        _make_item("BUTTER",  "B-004", IN_7_DAYS,  15, "Amul Butter 100g"),
        _make_item("CURD-C",  "B-005", YESTERDAY,  8,  "Flavoured Curd"),
        _make_item("MANGO",   "B-006", IN_30_DAYS, 30, "Mango Pulp 500g"),
    ]

    def _get(self, qs=None):
        return _inv({
            "httpMethod":            "GET",
            "resource":              "/inventory",
            "queryStringParameters": qs,
        }, INV_ENV)

    def test_fefo_order_ascending(self):
        _seed(self.tables["inventory"], self.FEFO_ITEMS)
        resp = self._get()
        assert resp["statusCode"] == 200
        items = json.loads(resp["body"])["items"]
        assert len(items) == len(self.FEFO_ITEMS)
        dates = [i["expiryDate"] for i in items]
        assert dates == sorted(dates), f"NOT FEFO order: {dates}"

    def test_expired_items_appear_first(self):
        _seed(self.tables["inventory"], self.FEFO_ITEMS)
        items = json.loads(self._get()["body"])["items"]
        today_s = TODAY.isoformat()
        first_ok = next((i for i, x in enumerate(items) if x["expiryDate"] >= today_s), len(items))
        for item in items[:first_ok]:
            assert item["expiryDate"] < today_s, \
                f"Expired item found after a non-expired one: {item['id']}"

    def test_fefo_single_item(self):
        _seed(self.tables["inventory"], [_make_item("SOLO-X", "B-SOLO", IN_7_DAYS, 5)])
        body = json.loads(self._get()["body"])
        assert body["count"] == 1
        assert body["items"][0]["sku"] == "SOLO-X"

    def test_fefo_empty_inventory(self):
        resp = self._get()
        body = json.loads(resp["body"])
        assert resp["statusCode"] == 200
        assert body["items"] == []
        assert body["count"] == 0

    def test_sku_filter_returns_correct_subset(self):
        _seed(self.tables["inventory"], [
            _make_item("MILK-1L", "BATCH-A", IN_7_DAYS,  10, "Whole Milk"),
            _make_item("MILK-1L", "BATCH-B", IN_3_DAYS,  5,  "Whole Milk"),
            _make_item("BREAD-W", "BATCH-C", IN_10_DAYS, 20, "Bread"),
        ])
        items = json.loads(self._get({"sku": "MILK-1L"})["body"])["items"]
        assert len(items) == 2
        assert all(i["sku"] == "MILK-1L" for i in items)

    def test_same_expiry_both_returned(self):
        _seed(self.tables["inventory"], [
            _make_item("SKU-A", "BT-1", IN_7_DAYS, 10, "Product A"),
            _make_item("SKU-B", "BT-2", IN_7_DAYS, 20, "Product B"),
        ])
        items = json.loads(self._get()["body"])["items"]
        assert len(items) == 2
        assert items[0]["expiryDate"] == items[1]["expiryDate"] == IN_7_DAYS

    def test_seed_data_file_integrity(self):
        seed_path = Path(__file__).resolve().parent.parent / "data" / "seed_inventory.json"
        assert seed_path.exists(), f"Seed file missing: {seed_path}"
        # utf-8-sig handles optional BOM produced by some editors on Windows
        with open(seed_path, encoding="utf-8-sig") as f:
            items = json.load(f)
        real = [i for i in items if "id" in i]
        assert len(real) >= 25, f"Expected >= 25 items, got {len(real)}"
        for item in real:
            exp = item.get("expiryDate", "")
            assert len(exp) == 10 and exp[4] == "-" and exp[7] == "-", \
                f"Bad expiryDate in {item.get('id')}: {exp!r}"
            assert item.get("quantity", -1) > 0, \
                f"Non-positive quantity in {item.get('id')}"
            assert item.get("productName"), f"Missing productName in {item.get('id')}"


# ===========================================================================
# Suite 2 -- Expiry Alert Threshold
# ===========================================================================

class TestExpiryAlertThreshold:
    """alertService finds items within the 7-day window and publishes to SNS."""

    @pytest.fixture(autouse=True)
    def _setup(self, dynamodb_tables, sns_topic):
        self.tables    = dynamodb_tables
        self.topic_arn = sns_topic

    def _items(self):
        return [
            _make_item("A1", "BA-1", IN_3_DAYS,  10, "Expiring Soon A"),
            _make_item("A2", "BA-2", IN_7_DAYS,  5,  "Expiring Soon B"),
            _make_item("A3", "BA-3", IN_10_DAYS, 20, "Safe Product A"),
            _make_item("A4", "BA-4", IN_30_DAYS, 30, "Safe Product B"),
            _make_item("A5", "BA-5", YESTERDAY,  8,  "Already Expired A"),
            _make_item("A6", "BA-6", LAST_WEEK,  3,  "Already Expired B"),
        ]

    def test_alert_detects_expiring_items(self):
        _seed(self.tables["inventory"], self._items())
        result = _alert({**ALERT_ENV_BASE, "SNS_TOPIC_ARN": self.topic_arn})
        assert result["status"] == "ok", f"Unexpected error: {result}"
        assert result["itemsFound"] == 4, f"Expected 4, got {result['itemsFound']}"
        assert result["alertsSent"] == 1
        assert "snsMessageId" in result

    def test_alert_summary_expired_vs_expiring(self):
        _seed(self.tables["inventory"], self._items())
        summary = _alert({**ALERT_ENV_BASE, "SNS_TOPIC_ARN": self.topic_arn}).get("summary", {})
        assert summary.get("expired")  == 2, f"Expired count wrong: {summary}"
        assert summary.get("expiring") == 2, f"Expiring count wrong: {summary}"

    def test_no_alert_when_all_items_safe(self):
        _seed(self.tables["inventory"], [
            _make_item("S1", "BS-1", IN_10_DAYS, 10, "Safe Milk"),
            _make_item("S2", "BS-2", IN_30_DAYS, 20, "Safe Bread"),
        ])
        result = _alert({**ALERT_ENV_BASE, "SNS_TOPIC_ARN": self.topic_arn})
        assert result["status"] == "ok"
        assert result.get("alertsSent", 0) == 0
        assert "snsMessageId" not in result

    def test_boundary_exactly_7_days_triggers_alert(self):
        _seed(self.tables["inventory"],
              [_make_item("BOUND-X", "BB-1", IN_7_DAYS, 5, "Boundary Item")])
        result = _alert({**ALERT_ENV_BASE, "SNS_TOPIC_ARN": self.topic_arn})
        assert result.get("itemsFound", 0) >= 1, "Day-7 boundary item must trigger the alert"

    def test_8_days_does_not_trigger_alert(self):
        eight_days = (TODAY + timedelta(days=8)).isoformat()
        _seed(self.tables["inventory"],
              [_make_item("FAR-OUT", "BF-1", eight_days, 10, "Far Future")])
        result = _alert({**ALERT_ENV_BASE, "SNS_TOPIC_ARN": self.topic_arn})
        assert result.get("itemsFound", 0) == 0, \
            "Item expiring in 8 days should not trigger a 7-day alert"

    def test_zero_quantity_excluded_from_alert(self):
        _seed(self.tables["inventory"],
              [_make_item("EMPTY-Z", "BZ-1", IN_3_DAYS, 0, "Out of Stock")])
        result = _alert({**ALERT_ENV_BASE, "SNS_TOPIC_ARN": self.topic_arn})
        assert result.get("itemsFound", 0) == 0, "Zero-quantity items must not trigger alerts"

    def test_missing_sns_arn_returns_error(self):
        _seed(self.tables["inventory"],
              [_make_item("ERR-X", "BE-1", IN_3_DAYS, 5, "Error Test")])
        result = _alert({**ALERT_ENV_BASE, "SNS_TOPIC_ARN": ""})
        assert result["status"] == "error"


# ===========================================================================
# Suite 3 -- Stock Dispatch (Atomic Decrement)
# ===========================================================================

class TestStockDispatch:
    """POST /dispatch atomically decrements stock and prevents over-dispatch."""

    BASE_ITEM = _make_item("DISPATCH-SKU", "BD-001", IN_30_DAYS, 50, "Dispatchable Item")

    @pytest.fixture(autouse=True)
    def _setup(self, dynamodb_tables):
        self.tables = dynamodb_tables

    def _dispatch(self, sku, batch, qty):
        return _inv({
            "httpMethod": "POST",
            "resource":   "/dispatch",
            "body": json.dumps({
                "sku": sku, "batchNumber": batch,
                "quantity": qty, "actor": "test-runner",
            }),
        }, INV_ENV)

    def test_dispatch_decrements_correctly(self):
        _seed(self.tables["inventory"], [self.BASE_ITEM])
        resp = self._dispatch("DISPATCH-SKU", "BD-001", 15)
        assert resp["statusCode"] == 200
        assert json.loads(resp["body"])["remainingStock"] == 35

    def test_dispatch_full_stock_to_zero(self):
        _seed(self.tables["inventory"], [self.BASE_ITEM])
        resp = self._dispatch("DISPATCH-SKU", "BD-001", 50)
        assert resp["statusCode"] == 200
        assert json.loads(resp["body"])["remainingStock"] == 0

    def test_dispatch_over_stock_returns_409(self):
        _seed(self.tables["inventory"], [self.BASE_ITEM])
        resp = self._dispatch("DISPATCH-SKU", "BD-001", 51)
        assert resp["statusCode"] == 409
        body = json.loads(resp["body"])
        assert "Insufficient stock" in body["error"]
        assert body["availableStock"]  == 50
        assert body["requestedAmount"] == 51

    def test_dispatch_nonexistent_batch_returns_404(self):
        resp = self._dispatch("GHOST-SKU", "BD-GHOST", 5)
        assert resp["statusCode"] == 404
        assert "not found" in json.loads(resp["body"])["error"].lower()

    def test_dispatch_zero_quantity_returns_400(self):
        _seed(self.tables["inventory"], [self.BASE_ITEM])
        resp = self._dispatch("DISPATCH-SKU", "BD-001", 0)
        assert resp["statusCode"] == 400

    def test_dispatch_negative_quantity_returns_400(self):
        _seed(self.tables["inventory"], [self.BASE_ITEM])
        resp = self._dispatch("DISPATCH-SKU", "BD-001", -5)
        assert resp["statusCode"] == 400

    def test_sequential_dispatches_are_cumulative(self):
        _seed(self.tables["inventory"], [self.BASE_ITEM])
        expected = 50
        for qty in [10, 15, 5, 20]:
            resp = self._dispatch("DISPATCH-SKU", "BD-001", qty)
            expected -= qty
            assert resp["statusCode"] == 200, \
                f"Dispatch of {qty} failed: {resp['body']}"
            assert json.loads(resp["body"])["remainingStock"] == expected

    def test_dispatch_missing_quantity_field_returns_400(self):
        resp = _inv({
            "httpMethod": "POST",
            "resource":   "/dispatch",
            "body": json.dumps({"sku": "X", "batchNumber": "B-X"}),
        }, INV_ENV)
        assert resp["statusCode"] == 400
        assert "quantity" in json.loads(resp["body"])["error"].lower()


# ===========================================================================
# Suite 4 -- Inventory Upsert (POST /inventory)
# ===========================================================================

class TestInventoryUpsert:
    """POST /inventory creates new records and upserts existing ones correctly."""

    @pytest.fixture(autouse=True)
    def _setup(self, dynamodb_tables):
        self.tables = dynamodb_tables

    def _post(self, body):
        return _inv({
            "httpMethod": "POST",
            "resource":   "/inventory",
            "body":       json.dumps(body),
        }, INV_ENV)

    def test_create_new_item_returns_201(self):
        resp = self._post({
            "productName": "Test Milk 500ml", "sku": "TST-MILK-500",
            "batchNumber": "BTN-20260824",    "expiryDate": IN_30_DAYS,
            "quantity": 25, "storageGuideline": "Store below 4C",
        })
        assert resp["statusCode"] == 201
        body = json.loads(resp["body"])
        assert body["id"] == "BTN-20260824#TST-MILK-500"
        assert body["quantity"] == 25

    def test_upsert_preserves_created_at(self):
        original = _make_item("UPS-SKU", "BU-001", IN_30_DAYS, 20, "Upsert Test")
        _seed(self.tables["inventory"], [original])
        resp = self._post({
            "productName": "Upsert Test", "sku": "UPS-SKU",
            "batchNumber": "BU-001",      "expiryDate": IN_30_DAYS,
            "quantity": 45, "storageGuideline": "Refrigerate",
        })
        assert resp["statusCode"] == 201
        body = json.loads(resp["body"])
        assert body["quantity"] == 45
        assert body["createdAt"] == original["createdAt"]

    def test_missing_required_fields_returns_400(self):
        resp = self._post({"productName": "Incomplete", "sku": "INC-001"})
        assert resp["statusCode"] == 400
        assert "Missing required fields" in json.loads(resp["body"])["error"]

    def test_options_preflight_returns_200(self):
        resp = _inv({"httpMethod": "OPTIONS", "resource": "/inventory", "body": None}, INV_ENV)
        assert resp["statusCode"] == 200
        assert "Access-Control-Allow-Origin" in resp["headers"]

    def test_unknown_route_returns_404(self):
        resp = _inv({"httpMethod": "DELETE", "resource": "/does-not-exist", "body": None}, INV_ENV)
        assert resp["statusCode"] == 404