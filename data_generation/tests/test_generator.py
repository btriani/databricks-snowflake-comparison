import pandas as pd
import pytest

from data_generation.generator import generate_customers


def test_generate_customers_produces_expected_schema(fixed_seed):
    df = generate_customers(n=10, seed=fixed_seed)
    expected_columns = {
        "cc_num", "first", "last", "gender", "street", "city", "state",
        "zip", "lat", "long", "city_pop", "job", "dob",
    }
    assert set(df.columns) == expected_columns
    assert len(df) == 10


def test_generate_customers_is_deterministic(fixed_seed):
    df1 = generate_customers(n=50, seed=fixed_seed)
    df2 = generate_customers(n=50, seed=fixed_seed)
    pd.testing.assert_frame_equal(df1, df2)


def test_generate_customers_unique_cc_num(fixed_seed):
    df = generate_customers(n=1000, seed=fixed_seed)
    assert df["cc_num"].is_unique


def test_generate_customers_cc_num_is_16_digit_string(fixed_seed):
    df = generate_customers(n=20, seed=fixed_seed)
    assert df["cc_num"].dtype == object
    assert df["cc_num"].str.len().eq(16).all()
    assert df["cc_num"].str.isdigit().all()


from data_generation.generator import generate_merchants, MERCHANT_CATEGORIES


def test_generate_merchants_schema(fixed_seed):
    df = generate_merchants(n=20, seed=fixed_seed)
    assert set(df.columns) == {"merchant", "category", "merch_lat", "merch_long"}
    assert len(df) == 20


def test_generate_merchants_categories_from_fixed_set(fixed_seed):
    df = generate_merchants(n=200, seed=fixed_seed)
    assert set(df["category"]).issubset(MERCHANT_CATEGORIES)


def test_generate_merchants_unique_merchant_name(fixed_seed):
    df = generate_merchants(n=100, seed=fixed_seed)
    assert df["merchant"].is_unique


from datetime import datetime

from data_generation.generator import generate_transactions


def test_generate_transactions_schema(fixed_seed):
    customers = generate_customers(n=10, seed=fixed_seed)
    merchants = generate_merchants(n=5, seed=fixed_seed)
    txns = generate_transactions(
        customers=customers,
        merchants=merchants,
        n=100,
        seed=fixed_seed,
        start=datetime(2026, 1, 1),
        end=datetime(2026, 2, 1),
    )
    expected = {
        "cc_num", "merchant", "category", "amt", "trans_date_trans_time",
        "lat", "long", "city", "state", "zip", "city_pop", "job", "dob",
        "trans_num", "unix_time", "merch_lat", "merch_long",
    }
    assert set(txns.columns) == expected
    assert len(txns) == 100


def test_generate_transactions_cc_num_in_customers(fixed_seed):
    customers = generate_customers(n=10, seed=fixed_seed)
    merchants = generate_merchants(n=5, seed=fixed_seed)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=500, seed=fixed_seed,
        start=datetime(2026, 1, 1), end=datetime(2026, 2, 1),
    )
    assert txns["cc_num"].isin(customers["cc_num"]).all()


def test_generate_transactions_unique_trans_num(fixed_seed):
    customers = generate_customers(n=10, seed=fixed_seed)
    merchants = generate_merchants(n=5, seed=fixed_seed)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=500, seed=fixed_seed,
        start=datetime(2026, 1, 1), end=datetime(2026, 2, 1),
    )
    assert txns["trans_num"].is_unique


def test_generate_transactions_amt_positive(fixed_seed):
    customers = generate_customers(n=10, seed=fixed_seed)
    merchants = generate_merchants(n=5, seed=fixed_seed)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=500, seed=fixed_seed,
        start=datetime(2026, 1, 1), end=datetime(2026, 2, 1),
    )
    assert (txns["amt"] > 0).all()


from data_generation.generator import inject_fraud_labels


def test_inject_fraud_labels_adds_column(fixed_seed):
    customers = generate_customers(n=10, seed=fixed_seed)
    merchants = generate_merchants(n=5, seed=fixed_seed)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=10000, seed=fixed_seed,
        start=datetime(2026, 1, 1), end=datetime(2026, 2, 1),
    )
    labeled = inject_fraud_labels(txns, target_rate=0.01, seed=fixed_seed)
    assert "is_fraud" in labeled.columns
    assert labeled["is_fraud"].isin([0, 1]).all()


def test_inject_fraud_labels_rate_within_bounds(fixed_seed):
    customers = generate_customers(n=10, seed=fixed_seed)
    merchants = generate_merchants(n=5, seed=fixed_seed)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=20000, seed=fixed_seed,
        start=datetime(2026, 1, 1), end=datetime(2026, 2, 1),
    )
    labeled = inject_fraud_labels(txns, target_rate=0.01, seed=fixed_seed)
    rate = labeled["is_fraud"].mean()
    assert 0.005 <= rate <= 0.02


def test_inject_fraud_labels_correlates_with_amount(fixed_seed):
    customers = generate_customers(n=10, seed=fixed_seed)
    merchants = generate_merchants(n=5, seed=fixed_seed)
    txns = generate_transactions(
        customers=customers, merchants=merchants, n=20000, seed=fixed_seed,
        start=datetime(2026, 1, 1), end=datetime(2026, 2, 1),
    )
    labeled = inject_fraud_labels(txns, target_rate=0.01, seed=fixed_seed)
    fraud_mean_amt = labeled.loc[labeled["is_fraud"] == 1, "amt"].mean()
    legit_mean_amt = labeled.loc[labeled["is_fraud"] == 0, "amt"].mean()
    assert fraud_mean_amt > legit_mean_amt
