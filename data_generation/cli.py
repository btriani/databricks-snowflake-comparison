"""CLI entry point for synthetic data generation."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

import click

from data_generation.dirt import apply_all_dirt
from data_generation.generator import (
    generate_customers,
    generate_merchants,
    generate_transactions,
    inject_fraud_labels,
)


BANKS_STUB_CSV = (
    "RSSD_ID,NAME,CITY,STATE,CHARTER_CLASS,PRIMARY_FED_REG\n"
    "12345,Bank of NorthWind,Wilmington,DE,N,OCC\n"
    "67890,Demo Credit Union,Austin,TX,SB,FDIC\n"
    "11111,Test National Bank,New York,NY,N,OCC\n"
    "22222,Pacific Federal Bank,San Francisco,CA,SA,OTS\n"
    "33333,Mountain State Bank,Denver,CO,N,FDIC\n"
)


def _write_banks_stub(output: Path) -> int:
    """Write the FFIEC stub bank dim to output/banks.parquet. Returns row count.

    A 5-row stub is sufficient for M2a/M2b/M2c — the silver-layer story is about
    *joining* to a reference dim, not about real bank data. The fetcher in
    data_generation/ffiec.py can be wired in later for richer reference data.
    """
    import io as _io
    import pandas as _pd
    df = _pd.read_csv(_io.StringIO(BANKS_STUB_CSV))
    df.columns = [c.lower() for c in df.columns]
    df = df.rename(columns={
        "name": "bank_name",
        "primary_fed_reg": "primary_federal_regulator",
    })
    df.to_parquet(output / "banks.parquet", index=False)
    return len(df)


def _write_dirty(df: "pd.DataFrame", path: Path) -> None:
    """Write a potentially dirty DataFrame to parquet.

    Mixed-type object columns (e.g. amt after type-drift injection) are cast
    to string so pyarrow can serialise them without a schema error.
    """
    import pandas as pd

    out = df.copy()
    for col in out.columns:
        if out[col].dtype == object:
            # Check if any value is not a string — mixed numeric+string column
            non_str = out[col].dropna().map(lambda x: not isinstance(x, str))
            if non_str.any():
                out[col] = out[col].map(lambda x: str(x) if pd.notna(x) else x)
    out.to_parquet(path, index=False)


@click.command()
@click.option("--rows", default=100_000, show_default=True, help="Number of transactions to generate.")
@click.option("--customers", default=10_000, show_default=True, help="Number of customers.")
@click.option("--merchants", default=1_000, show_default=True, help="Number of merchants.")
@click.option("--fraud-rate", default=0.01, show_default=True, help="Target fraud rate (0..1).")
@click.option("--seed", default=42, show_default=True, help="RNG seed.")
@click.option("--start", default="2026-01-01", show_default=True, help="Earliest transaction date (YYYY-MM-DD).")
@click.option("--end", default="2026-04-01", show_default=True, help="Latest transaction date (YYYY-MM-DD, exclusive).")
@click.option(
    "--output", required=True,
    type=click.Path(file_okay=False, dir_okay=True, path_type=Path),
    help="Landing directory; parquet files written here.",
)
def generate(rows: int, customers: int, merchants: int, fraud_rate: float,
             seed: int, start: str, end: str, output: Path) -> None:
    """Generate NorthWind Payments synthetic data with deliberate dirt."""
    output.mkdir(parents=True, exist_ok=True)

    click.echo(f"[1/5] Generating {customers:,} customers...")
    cust_df = generate_customers(n=customers, seed=seed)

    click.echo(f"[2/5] Generating {merchants:,} merchants...")
    merch_df = generate_merchants(n=merchants, seed=seed)

    click.echo(f"[3/5] Generating {rows:,} transactions and injecting fraud...")
    txns = generate_transactions(
        customers=cust_df, merchants=merch_df, n=rows, seed=seed,
        start=datetime.fromisoformat(start),
        end=datetime.fromisoformat(end),
    )
    labeled = inject_fraud_labels(txns, target_rate=fraud_rate, seed=seed)

    click.echo("[4/5] Applying dirt and splitting v1/v2 + late...")
    v1c, v1l, v2c, v2l = apply_all_dirt(
        labeled, valid_cc_nums=set(cust_df["cc_num"]), seed=seed,
    )

    cust_df.to_parquet(output / "customers.parquet", index=False)
    merch_df.to_parquet(output / "merchants.parquet", index=False)
    _write_dirty(v1c, output / "transactions_v1_current.parquet")
    _write_dirty(v1l, output / "transactions_v1_late.parquet")
    _write_dirty(v2c, output / "transactions_v2_current.parquet")
    _write_dirty(v2l, output / "transactions_v2_late.parquet")

    n_banks = _write_banks_stub(output)
    click.echo(f"[5/5] Wrote {n_banks} bank rows to {output}/banks.parquet")

    click.echo(f"Done. Wrote 7 files to {output}")


if __name__ == "__main__":
    generate()
