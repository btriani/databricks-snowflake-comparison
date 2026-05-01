"""Tests for M2a Databricks artifacts: scripts and bundle config syntax."""

from pathlib import Path
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_preflight_script_exists_and_is_executable():
    path = REPO_ROOT / "scripts" / "databricks_preflight.sh"
    assert path.exists(), f"missing: {path}"
    assert path.stat().st_mode & 0o111, "preflight script not executable"


def test_preflight_script_passes_shellcheck_or_bash_n():
    """Validate the script with `bash -n` (syntax-only). Does not run the script."""
    path = REPO_ROOT / "scripts" / "databricks_preflight.sh"
    result = subprocess.run(
        ["bash", "-n", str(path)],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, f"bash -n failed: {result.stderr}"


def test_env_example_contains_databricks_host():
    path = REPO_ROOT / ".env.example"
    text = path.read_text()
    assert "DATABRICKS_HOST" in text
    assert "DATABRICKS_TOKEN" in text


def test_uc_setup_sql_has_expected_objects():
    path = REPO_ROOT / "databricks" / "notebooks" / "01_setup_uc.sql"
    assert path.exists()
    text = path.read_text()
    assert "CREATE CATALOG IF NOT EXISTS northwind_payments" in text
    assert "CREATE SCHEMA IF NOT EXISTS northwind_payments.bronze" in text
    assert "CREATE SCHEMA IF NOT EXISTS northwind_payments._quarantine" in text
    assert "CREATE VOLUME IF NOT EXISTS northwind_payments.bronze.landing" in text
    assert "'project' = 'northwind-payments'" in text


def test_setup_uc_script_passes_bash_n():
    path = REPO_ROOT / "scripts" / "setup_uc.sh"
    result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_push_landing_script_passes_bash_n():
    path = REPO_ROOT / "scripts" / "push_landing_to_volume.sh"
    assert path.exists()
    result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_push_landing_script_references_volume_path():
    path = REPO_ROOT / "scripts" / "push_landing_to_volume.sh"
    text = path.read_text()
    assert "/Volumes/northwind_payments/bronze/landing" in text


def test_load_banks_sql_creates_bronze_banks_table():
    path = REPO_ROOT / "databricks" / "notebooks" / "03_load_banks.sql"
    assert path.exists()
    text = path.read_text()
    assert "CREATE TABLE IF NOT EXISTS northwind_payments.bronze.banks" in text
    assert "COPY INTO northwind_payments.bronze.banks" in text
    assert "/Volumes/northwind_payments/bronze/landing/reference/" in text


import yaml


def test_bundle_yaml_parses():
    path = REPO_ROOT / "databricks" / "bundle" / "databricks.yml"
    assert path.exists()
    cfg = yaml.safe_load(path.read_text())
    assert cfg["bundle"]["name"] == "northwind-payments-m2a"
    job = cfg["resources"]["jobs"]["bronze_ingest"]
    assert job["tags"]["project"] == "northwind-payments"
    task_keys = {t["task_key"] for t in job["tasks"]}
    assert task_keys == {"load_banks", "autoloader_bronze"}


def test_autoloader_notebook_uses_schema_evolution_mode():
    path = REPO_ROOT / "databricks" / "notebooks" / "02_autoloader_bronze.py"
    text = path.read_text()
    assert 'cloudFiles.schemaEvolutionMode' in text
    assert "addNewColumns" in text
    assert "_ingest_timestamp" in text
    assert "_source_file" in text


def test_verify_bronze_sql_exists_with_required_queries():
    path = REPO_ROOT / "databricks" / "queries" / "verify_bronze.sql"
    text = path.read_text()
    assert "system.information_schema.table_tags" in text
    assert "northwind_payments.bronze.transactions" in text
    assert "northwind_payments.bronze.customers" in text
    assert "northwind_payments.bronze.banks" in text
