import subprocess
from pathlib import Path


def test_smoke_pytest_runs():
    assert 1 + 1 == 2


def test_databricks_cost_notebook_exists():
    path = Path(__file__).resolve().parents[2] / "databricks" / "notebooks" / "cost_tracking.py"
    assert path.exists()
    text = path.read_text()
    assert "system.billing.usage" in text
    assert "northwind-payments" in text


def test_snowflake_cost_sql_exists():
    path = Path(__file__).resolve().parents[2] / "snowflake" / "notebooks" / "cost_tracking.sql"
    assert path.exists()
    text = path.read_text()
    assert "WAREHOUSE_METERING_HISTORY" in text
    assert "NORTHWIND" in text


def test_teardown_script_runs_without_error():
    repo_root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        ["bash", "scripts/teardown.sh", "local"],
        cwd=repo_root, check=False, capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr


def test_teardown_script_passes_bash_n_after_databricks_extension():
    repo_root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        ["bash", "-n", "scripts/teardown.sh"],
        cwd=repo_root, check=False, capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
