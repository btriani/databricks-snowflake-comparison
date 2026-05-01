from pathlib import Path

from click.testing import CliRunner

from data_generation.cli import generate


def test_generate_cli_smoke_writes_files(tmp_path):
    runner = CliRunner()
    result = runner.invoke(generate, [
        "--rows", "500",
        "--customers", "20",
        "--merchants", "10",
        "--seed", "42",
        "--output", str(tmp_path),
    ])
    assert result.exit_code == 0, result.output

    files = sorted(p.name for p in tmp_path.glob("**/*.parquet"))
    assert any("transactions_v1_current" in f for f in files)
    assert any("transactions_v1_late" in f for f in files)
    assert any("transactions_v2_current" in f for f in files)
    assert any("transactions_v2_late" in f for f in files)
    assert any("customers" in f for f in files)
    assert any("merchants" in f for f in files)
    assert any("banks" in f for f in files)


def test_generate_cli_is_deterministic_across_runs(tmp_path):
    import pandas as pd
    out_a = tmp_path / "a"
    out_b = tmp_path / "b"
    runner = CliRunner()
    runner.invoke(generate, [
        "--rows", "500", "--customers", "20", "--merchants", "10",
        "--seed", "42", "--output", str(out_a),
    ])
    runner.invoke(generate, [
        "--rows", "500", "--customers", "20", "--merchants", "10",
        "--seed", "42", "--output", str(out_b),
    ])
    df_a = pd.read_parquet(out_a / "customers.parquet")
    df_b = pd.read_parquet(out_b / "customers.parquet")
    pd.testing.assert_frame_equal(df_a, df_b)
