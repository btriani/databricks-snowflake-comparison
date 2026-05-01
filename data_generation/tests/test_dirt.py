import pandas as pd
import pytest

from data_generation.dirt import inject_nulls


def test_inject_nulls_adds_nulls_at_target_rate():
    df = pd.DataFrame({
        "cc_num": ["1234567890123456"] * 1000,
        "amt": [10.0] * 1000,
    })
    dirty = inject_nulls(df, columns=["cc_num"], rate=0.05, seed=42)
    null_share = dirty["cc_num"].isna().mean()
    assert 0.03 <= null_share <= 0.07


def test_inject_nulls_does_not_touch_other_columns():
    df = pd.DataFrame({
        "cc_num": ["1234567890123456"] * 1000,
        "amt": [10.0] * 1000,
    })
    dirty = inject_nulls(df, columns=["cc_num"], rate=0.10, seed=42)
    assert dirty["amt"].isna().sum() == 0


def test_inject_nulls_returns_same_length():
    df = pd.DataFrame({"cc_num": ["x"] * 100})
    dirty = inject_nulls(df, columns=["cc_num"], rate=0.5, seed=42)
    assert len(dirty) == 100


def test_inject_nulls_validates_columns_exist():
    df = pd.DataFrame({"cc_num": ["x"] * 10})
    with pytest.raises(KeyError):
        inject_nulls(df, columns=["does_not_exist"], rate=0.1, seed=42)


from data_generation.dirt import inject_duplicates


def test_inject_duplicates_increases_row_count():
    df = pd.DataFrame({"trans_num": [f"t{i}" for i in range(1000)]})
    dirty = inject_duplicates(df, rate=0.01, seed=42)
    assert len(dirty) > len(df)
    assert len(dirty) <= len(df) * 1.05


def test_inject_duplicates_creates_repeated_keys():
    df = pd.DataFrame({"trans_num": [f"t{i}" for i in range(1000)]})
    dirty = inject_duplicates(df, rate=0.05, seed=42)
    counts = dirty["trans_num"].value_counts()
    assert (counts > 1).sum() > 0


def test_inject_duplicates_preserves_other_columns():
    df = pd.DataFrame({
        "trans_num": [f"t{i}" for i in range(100)],
        "amt": list(range(100)),
    })
    dirty = inject_duplicates(df, rate=0.05, seed=42)
    assert "amt" in dirty.columns


from datetime import datetime, timedelta

from data_generation.dirt import split_late_arrivers


def test_split_late_arrivers_returns_two_frames():
    base = datetime(2026, 1, 15, 12, 0, 0)
    df = pd.DataFrame({
        "trans_date_trans_time": pd.date_range(base, periods=1000, freq="60s"),
        "amt": list(range(1000)),
    })
    current, late = split_late_arrivers(df, late_rate=0.05, max_lateness_days=3, seed=42)
    assert len(current) + len(late) == 1000
    assert 0.03 <= len(late) / 1000 <= 0.07


def test_split_late_arrivers_late_timestamps_are_earlier():
    base = datetime(2026, 1, 15, 12, 0, 0)
    df = pd.DataFrame({
        "trans_date_trans_time": [base] * 100,
        "amt": list(range(100)),
    })
    current, late = split_late_arrivers(df, late_rate=0.20, max_lateness_days=3, seed=42)
    if len(late):
        assert (late["trans_date_trans_time"] < base).all()


def test_split_late_arrivers_zero_rate_returns_empty_late():
    base = datetime(2026, 1, 15)
    df = pd.DataFrame({
        "trans_date_trans_time": [base] * 50,
        "amt": [1.0] * 50,
    })
    current, late = split_late_arrivers(df, late_rate=0.0, max_lateness_days=3, seed=42)
    assert len(late) == 0
    assert len(current) == 50


from data_generation.dirt import to_v2_schema


def test_to_v2_schema_renames_amt_column():
    df = pd.DataFrame({"trans_num": ["x"], "amt": [1.0], "cc_num": ["y"]})
    v2 = to_v2_schema(df, seed=42)
    assert "amt" not in v2.columns
    assert "transaction_amount" in v2.columns
    assert v2["transaction_amount"].iloc[0] == 1.0


def test_to_v2_schema_adds_device_id_column():
    df = pd.DataFrame({"trans_num": ["x"] * 100, "amt": [1.0] * 100})
    v2 = to_v2_schema(df, seed=42)
    assert "device_id" in v2.columns
    assert v2["device_id"].notna().all()
    assert v2["device_id"].dtype == object


def test_to_v2_schema_device_id_is_deterministic():
    df = pd.DataFrame({"trans_num": ["x"] * 50, "amt": [1.0] * 50})
    v2_a = to_v2_schema(df, seed=42)
    v2_b = to_v2_schema(df, seed=42)
    pd.testing.assert_series_equal(v2_a["device_id"], v2_b["device_id"])


from data_generation.dirt import inject_bad_joins


def test_inject_bad_joins_replaces_some_cc_nums():
    valid_ccs = {"1111222233334444", "5555666677778888"}
    df = pd.DataFrame({"cc_num": ["1111222233334444"] * 1000})
    dirty = inject_bad_joins(df, valid_cc_nums=valid_ccs, rate=0.05, seed=42)
    bad = ~dirty["cc_num"].isin(valid_ccs)
    assert 0.03 <= bad.mean() <= 0.07


def test_inject_bad_joins_preserves_row_count():
    df = pd.DataFrame({"cc_num": ["1111222233334444"] * 100})
    dirty = inject_bad_joins(df, valid_cc_nums={"1111222233334444"}, rate=0.10, seed=42)
    assert len(dirty) == 100


def test_inject_bad_joins_zero_rate_is_noop():
    df = pd.DataFrame({"cc_num": ["1111222233334444"] * 50})
    dirty = inject_bad_joins(df, valid_cc_nums={"1111222233334444"}, rate=0.0, seed=42)
    assert dirty.equals(df)


from data_generation.dirt import inject_type_drift


def test_inject_type_drift_creates_string_amts():
    df = pd.DataFrame({"amt": [1234.56] * 1000})
    dirty = inject_type_drift(df, column="amt", rate=0.05, seed=42)
    is_str = dirty["amt"].map(lambda x: isinstance(x, str))
    assert 0.03 <= is_str.mean() <= 0.07


def test_inject_type_drift_strings_have_dollar_and_comma():
    df = pd.DataFrame({"amt": [1234.56] * 100})
    dirty = inject_type_drift(df, column="amt", rate=1.0, seed=42)
    assert (dirty["amt"].astype(str).str.startswith("$")).all()
    assert (dirty["amt"].astype(str).str.contains(",", regex=False)).any()


def test_inject_type_drift_preserves_row_count():
    df = pd.DataFrame({"amt": [10.0] * 50})
    dirty = inject_type_drift(df, column="amt", rate=0.5, seed=42)
    assert len(dirty) == 50


from datetime import datetime

from data_generation.dirt import apply_all_dirt
from data_generation.generator import (
    generate_customers, generate_merchants, generate_transactions,
    inject_fraud_labels,
)


def test_apply_all_dirt_returns_four_frames():
    customers = generate_customers(n=20, seed=42)
    merchants = generate_merchants(n=10, seed=42)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=2000, seed=42,
        start=datetime(2026, 1, 1), end=datetime(2026, 1, 31),
    )
    labeled = inject_fraud_labels(txns, target_rate=0.01, seed=42)
    v1c, v1l, v2c, v2l = apply_all_dirt(
        labeled, valid_cc_nums=set(customers["cc_num"]), seed=42,
    )
    assert len(v1c) + len(v1l) + len(v2c) + len(v2l) >= 2000


def test_apply_all_dirt_v1_keeps_amt_column():
    customers = generate_customers(n=20, seed=42)
    merchants = generate_merchants(n=10, seed=42)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=500, seed=42,
        start=datetime(2026, 1, 1), end=datetime(2026, 1, 31),
    )
    labeled = inject_fraud_labels(txns, target_rate=0.01, seed=42)
    v1c, v1l, v2c, v2l = apply_all_dirt(
        labeled, valid_cc_nums=set(customers["cc_num"]), seed=42,
    )
    assert "amt" in v1c.columns
    assert "amt" in v1l.columns
    assert "transaction_amount" in v2c.columns
    assert "transaction_amount" in v2l.columns
    assert "device_id" in v2c.columns
