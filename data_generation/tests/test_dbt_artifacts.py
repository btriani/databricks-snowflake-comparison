"""Syntax tests for dbt project YAMLs and SQL files."""

from pathlib import Path
import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]
DBT_ROOT = REPO_ROOT / "dbt"


def test_dbt_project_yaml_parses():
    cfg = yaml.safe_load((DBT_ROOT / "dbt_project.yml").read_text())
    assert cfg["name"] == "northwind_payments"
    assert cfg["profile"] == "northwind_payments"
    assert cfg["vars"]["catalog"] == "northwind_payments"
    silver_cfg = cfg["models"]["northwind_payments"]["silver"]
    gold_cfg = cfg["models"]["northwind_payments"]["gold"]
    assert silver_cfg["+materialized"] == "table"
    assert silver_cfg["+schema"] == "silver"
    assert gold_cfg["+materialized"] == "table"
    assert gold_cfg["+schema"] == "gold"


def test_packages_yml_lists_dbt_utils():
    pkgs = yaml.safe_load((DBT_ROOT / "packages.yml").read_text())
    assert any(p.get("package") == "dbt-labs/dbt_utils" for p in pkgs["packages"])


def test_profiles_example_has_databricks_type():
    prof = yaml.safe_load((DBT_ROOT / "profiles" / "profiles.yml.example").read_text())
    assert prof["northwind_payments"]["outputs"]["dev"]["type"] == "databricks"


import subprocess


def test_render_dbt_profile_script_passes_bash_n():
    path = REPO_ROOT / "scripts" / "render_dbt_profile.sh"
    assert path.exists()
    assert path.stat().st_mode & 0o111, "script not executable"
    result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr


def test_singular_tests_directory_has_five_tests():
    singular = DBT_ROOT / "tests" / "singular"
    assert singular.exists()
    sql_files = sorted(singular.glob("*.sql"))
    assert len(sql_files) == 5, f"expected 5 singular tests, found {len(sql_files)}"
    for f in sql_files:
        assert "{{ ref(" in f.read_text(), f"{f.name} missing ref()"


def test_teardown_script_still_passes_bash_n():
    path = REPO_ROOT / "scripts" / "teardown.sh"
    result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
