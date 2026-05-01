"""Syntax + content tests for M2c governance and dashboard artifacts."""

from pathlib import Path
import json
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[2]
DBX = REPO_ROOT / "databricks"


def test_setup_security_sql_creates_four_masking_functions():
    text = (DBX / "notebooks" / "04_setup_security.sql").read_text()
    assert "CREATE SCHEMA IF NOT EXISTS northwind_payments.security" in text
    for fn in ("mask_cc_num", "mask_name", "mask_address", "mask_dob"):
        assert f"FUNCTION northwind_payments.security.{fn}" in text, f"missing function {fn}"
    assert "is_account_group_member('npl_pii_reader')" in text


def test_apply_security_script_passes_bash_n():
    path = REPO_ROOT / "scripts" / "apply_security.sh"
    assert path.exists()
    assert path.stat().st_mode & 0o111, "apply_security.sh not executable"
    r = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def test_apply_security_script_runs_three_sql_files():
    text = (REPO_ROOT / "scripts" / "apply_security.sh").read_text()
    for f in ("04_setup_security.sql", "05_apply_pii_masks.sql", "06_cleanup_legacy.sql"):
        assert f in text, f"apply_security.sh does not reference {f}"


def test_apply_pii_masks_sql_targets_five_columns_and_two_tables():
    text = (DBX / "notebooks" / "05_apply_pii_masks.sql").read_text()
    for col in ("cc_num", "first", "last", "street", "dob"):
        assert f"ALTER COLUMN {col} SET MASK" in text, f"missing mask on column {col}"
    assert text.count("northwind_payments.silver.transactions") >= 1
    assert "northwind_payments.silver.customers_snapshot" in text


def test_verify_pii_masks_sql_uses_information_schema():
    text = (DBX / "queries" / "verify_pii_masks.sql").read_text()
    assert "system.information_schema.column_masks" in text
    assert "system.information_schema.routines" in text


def test_cleanup_legacy_sql_drops_silver_silver():
    text = (DBX / "notebooks" / "06_cleanup_legacy.sql").read_text()
    assert "DROP SCHEMA IF EXISTS northwind_payments.silver_silver" in text


def test_dashboard_json_has_four_widgets_and_four_datasets():
    path = DBX / "dashboards" / "fraud_overview.lvdash.json"
    data = json.loads(path.read_text())
    assert len(data["datasets"]) == 4
    dataset_names = {d["name"] for d in data["datasets"]}
    assert dataset_names == {"kpi_today", "fraud_rate_timeseries", "fraud_by_category_state", "top_risk_merchants"}
    assert len(data["pages"]) == 1
    assert len(data["pages"][0]["layout"]) == 4


def test_dashboard_queries_reference_gold_tables():
    path = DBX / "dashboards" / "fraud_overview.lvdash.json"
    data = json.loads(path.read_text())
    all_sql = " ".join(line for ds in data["datasets"] for line in ds["queryLines"])
    assert "northwind_payments.gold.kpi_executive" in all_sql
    assert "northwind_payments.gold.fct_fraud_daily" in all_sql
    assert "northwind_payments.gold.fct_merchant_exposure" in all_sql


def test_deploy_dashboard_script_passes_bash_n():
    path = REPO_ROOT / "scripts" / "deploy_dashboard.sh"
    assert path.exists()
    assert path.stat().st_mode & 0o111, "deploy_dashboard.sh not executable"
    r = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def test_deploy_dashboard_references_correct_artifacts():
    text = (REPO_ROOT / "scripts" / "deploy_dashboard.sh").read_text()
    assert "fraud_overview.lvdash.json" in text
    assert "northwind-fraud-overview" in text
    assert ".dashboard_id" in text


def test_validate_cost_script_passes_bash_n():
    path = REPO_ROOT / "scripts" / "validate_cost.sh"
    assert path.exists()
    assert path.stat().st_mode & 0o111, "validate_cost.sh not executable"
    r = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
