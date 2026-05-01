"""Cross-platform parity check: Databricks vs Snowflake gold tables.

Runs reference queries against each platform and asserts:
- row counts match exactly
- numeric aggregates match within 1e-4 relative tolerance

Exits 0 on full parity, 1 on any mismatch. Load-bearing test for the
"same dbt spine, two platforms" comparison narrative in the brief.

Run: make parity-check  OR  uv run python scripts/parity_check.py
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path

ENV_PATH = Path(__file__).parent.parent / ".env"
if ENV_PATH.exists():
    for line in ENV_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip())

import requests
import snowflake.connector


DBX_HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
DBX_TOKEN = os.environ["DATABRICKS_TOKEN"]
SF_ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]
SF_USER = os.environ["SNOWFLAKE_USER"]
SF_PASSWORD = os.environ["SNOWFLAKE_PASSWORD"]
SF_ROLE = os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN")
SF_WAREHOUSE = os.environ.get("SNOWFLAKE_WAREHOUSE", "NORTHWIND_WH")
SF_DATABASE = os.environ.get("SNOWFLAKE_DATABASE", "NORTHWIND_PAYMENTS")


def get_databricks_warehouse_id() -> str:
    r = requests.get(
        f"{DBX_HOST}/api/2.0/sql/warehouses",
        headers={"Authorization": f"Bearer {DBX_TOKEN}"},
        timeout=30,
    )
    r.raise_for_status()
    warehouses = r.json().get("warehouses", [])
    starter = [w for w in warehouses if "starter" in w.get("name", "").lower()] or warehouses
    return starter[0]["id"]


DBX_WAREHOUSE_ID = get_databricks_warehouse_id()


def databricks_query(sql: str) -> list[list]:
    payload = {
        "warehouse_id": DBX_WAREHOUSE_ID,
        "statement": sql,
        "wait_timeout": "50s",
    }
    r = requests.post(
        f"{DBX_HOST}/api/2.0/sql/statements",
        headers={"Authorization": f"Bearer {DBX_TOKEN}"},
        json=payload,
        timeout=60,
    )
    r.raise_for_status()
    body = r.json()
    state = body["status"]["state"]
    if state != "SUCCEEDED":
        raise RuntimeError(f"Databricks: {state} — {body}")
    return body.get("result", {}).get("data_array", []) or []


def snowflake_query(sql: str) -> list[list]:
    conn = snowflake.connector.connect(
        account=SF_ACCOUNT, user=SF_USER, password=SF_PASSWORD,
        role=SF_ROLE, warehouse=SF_WAREHOUSE, database=SF_DATABASE,
    )
    try:
        cur = conn.cursor()
        cur.execute(sql)
        return [[str(c) if c is not None else None for c in row] for row in cur.fetchall()]
    finally:
        conn.close()


@dataclass
class ParityCheck:
    name: str
    databricks_sql: str
    snowflake_sql: str


CHECKS = [
    ParityCheck(
        "kpi_executive: rowcount + total fraud txn",
        "SELECT COUNT(*) AS rows, SUM(fraud_txn) AS fraud_txn_sum, SUM(total_txn) AS total_txn_sum FROM northwind_payments.gold.kpi_executive",
        "SELECT COUNT(*) AS n, SUM(fraud_txn) AS fraud_txn_sum, SUM(total_txn) AS total_txn_sum FROM NORTHWIND_PAYMENTS.GOLD.KPI_EXECUTIVE",
    ),
    ParityCheck(
        "fct_fraud_daily: rowcount + total txn count",
        "SELECT COUNT(*) AS rows, SUM(txn_count) AS txn_sum FROM northwind_payments.gold.fct_fraud_daily",
        "SELECT COUNT(*) AS n, SUM(txn_count) AS txn_sum FROM NORTHWIND_PAYMENTS.GOLD.FCT_FRAUD_DAILY",
    ),
    ParityCheck(
        "fct_merchant_exposure: rowcount + fraud_amt sum",
        "SELECT COUNT(*) AS rows, ROUND(SUM(fraud_amt), 2) AS fraud_amt_sum FROM northwind_payments.gold.fct_merchant_exposure",
        "SELECT COUNT(*) AS n, ROUND(SUM(fraud_amt), 2) AS fraud_amt_sum FROM NORTHWIND_PAYMENTS.GOLD.FCT_MERCHANT_EXPOSURE",
    ),
    ParityCheck(
        "dim_customer_risk: rowcount",
        "SELECT COUNT(*) AS rows FROM northwind_payments.gold.dim_customer_risk",
        "SELECT COUNT(*) AS n FROM NORTHWIND_PAYMENTS.GOLD.DIM_CUSTOMER_RISK",
    ),
]

TOLERANCE_REL = 1e-4


def values_match(d, s, tol=TOLERANCE_REL):
    if d is None and s is None:
        return True
    if d is None or s is None:
        return False
    try:
        df, sf = float(d), float(s)
    except (TypeError, ValueError):
        return str(d) == str(s)
    if df == sf:
        return True
    denom = max(abs(df), abs(sf))
    return denom == 0 or abs(df - sf) / denom <= tol


def main() -> int:
    print(f"[parity] Databricks warehouse {DBX_WAREHOUSE_ID}")
    print(f"[parity] Snowflake account {SF_ACCOUNT}")
    print()

    failures = 0
    for check in CHECKS:
        print(f"[parity] {check.name}")
        try:
            dbx = databricks_query(check.databricks_sql)
            sf = snowflake_query(check.snowflake_sql)
        except Exception as e:
            print(f"  ✗ query failed: {e}")
            failures += 1
            continue

        if not dbx or not sf:
            print("  ✗ no rows returned from one or both sides")
            failures += 1
            continue

        d_row, s_row = dbx[0], sf[0]
        if len(d_row) != len(s_row):
            print(f"  ✗ column count differs: dbx={len(d_row)} sf={len(s_row)}")
            failures += 1
            continue

        any_diff = False
        for i, (d, s) in enumerate(zip(d_row, s_row)):
            if not values_match(d, s):
                print(f"  ✗ col {i}: dbx={d!r} sf={s!r}")
                any_diff = True
        if any_diff:
            failures += 1
        else:
            print(f"  ✓ matched ({len(d_row)} cols: {d_row})")

    print()
    if failures:
        print(f"[parity] {failures}/{len(CHECKS)} CHECKS FAILED")
        return 1
    print(f"[parity] {len(CHECKS)}/{len(CHECKS)} checks passed (tolerance={TOLERANCE_REL})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
