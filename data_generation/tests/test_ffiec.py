import io
from pathlib import Path

import pandas as pd
import pytest
import responses

from data_generation.ffiec import fetch_institutions

SAMPLE_CSV = (
    "RSSD_ID,NAME,CITY,STATE,CHARTER_CLASS,PRIMARY_FED_REG\n"
    "12345,Bank of Test,Wilmington,DE,N,OCC\n"
    "67890,Demo Credit Union,Austin,TX,SB,FDIC\n"
)


@responses.activate
def test_fetch_institutions_writes_parquet(tmp_path):
    url = "https://example.com/ffiec_institutions.csv"
    responses.add(
        responses.GET, url, body=SAMPLE_CSV, status=200,
        content_type="text/csv",
    )
    out_path = tmp_path / "banks.parquet"
    fetch_institutions(url=url, output_path=out_path)
    assert out_path.exists()
    df = pd.read_parquet(out_path)
    assert len(df) == 2
    assert {"rssd_id", "bank_name", "city", "state",
            "charter_class", "primary_federal_regulator"}.issubset(df.columns)


@responses.activate
def test_fetch_institutions_raises_on_http_error(tmp_path):
    url = "https://example.com/ffiec_institutions.csv"
    responses.add(responses.GET, url, status=500)
    with pytest.raises(RuntimeError):
        fetch_institutions(url=url, output_path=tmp_path / "banks.parquet")


@responses.activate
def test_fetch_institutions_normalizes_column_names(tmp_path):
    url = "https://example.com/ffiec_institutions.csv"
    responses.add(responses.GET, url, body=SAMPLE_CSV, status=200)
    out_path = tmp_path / "banks.parquet"
    fetch_institutions(url=url, output_path=out_path)
    df = pd.read_parquet(out_path)
    assert all(c == c.lower() for c in df.columns)
