"""FFIEC institution reference data fetcher."""

from __future__ import annotations

import io
from pathlib import Path

import pandas as pd
import requests

COLUMN_RENAMES = {
    "rssd_id": "rssd_id",
    "name": "bank_name",
    "city": "city",
    "state": "state",
    "charter_class": "charter_class",
    "primary_fed_reg": "primary_federal_regulator",
}


def fetch_institutions(url: str, output_path: Path) -> None:
    """Download the FFIEC institutions CSV from `url` and write a normalized parquet.

    Raises RuntimeError on non-2xx response.
    """
    resp = requests.get(url, timeout=30)
    if not resp.ok:
        raise RuntimeError(
            f"FFIEC fetch failed: {resp.status_code} from {url}"
        )

    df = pd.read_csv(io.StringIO(resp.text))
    df.columns = [c.lower() for c in df.columns]
    df = df.rename(columns=COLUMN_RENAMES)

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(output_path, index=False)
