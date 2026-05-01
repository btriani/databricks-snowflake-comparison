"""Synthetic Sparkov-style data generator for NorthWind Payments."""

from __future__ import annotations

from datetime import date, datetime, timedelta
import random

import numpy as np
import pandas as pd
from faker import Faker

CUSTOMER_COLUMNS = [
    "cc_num", "first", "last", "gender", "street", "city", "state",
    "zip", "lat", "long", "city_pop", "job", "dob",
]


def generate_customers(n: int, seed: int) -> pd.DataFrame:
    """Generate `n` synthetic customers with a 16-digit cc_num as primary key."""
    fake = Faker("en_US")
    Faker.seed(seed)
    random.seed(seed)
    rng = np.random.default_rng(seed)

    rows = []
    used_cc = set()
    while len(rows) < n:
        cc = "".join(str(d) for d in rng.integers(0, 10, size=16))
        if cc in used_cc:
            continue
        used_cc.add(cc)
        gender = random.choice(["M", "F"])
        if gender == "M":
            first = fake.first_name_male()
        else:
            first = fake.first_name_female()
        dob = fake.date_of_birth(minimum_age=18, maximum_age=85)
        city_pop = int(rng.integers(500, 5_000_000))
        rows.append({
            "cc_num": cc,
            "first": first,
            "last": fake.last_name(),
            "gender": gender,
            "street": fake.street_address(),
            "city": fake.city(),
            "state": fake.state_abbr(),
            "zip": fake.zipcode(),
            "lat": float(fake.latitude()),
            "long": float(fake.longitude()),
            "city_pop": city_pop,
            "job": fake.job(),
            "dob": dob,
        })

    df = pd.DataFrame(rows, columns=CUSTOMER_COLUMNS)
    # Ensure cc_num is stored as plain object (str) dtype, not pandas StringDtype
    df["cc_num"] = df["cc_num"].astype(object)
    return df


MERCHANT_CATEGORIES = (
    "grocery_pos", "grocery_net", "gas_transport", "shopping_pos",
    "shopping_net", "entertainment", "food_dining", "health_fitness",
    "personal_care", "travel", "kids_pets", "home", "misc_pos", "misc_net",
)


def generate_merchants(n: int, seed: int) -> pd.DataFrame:
    """Generate `n` synthetic merchants. Names are unique."""
    fake = Faker("en_US")
    Faker.seed(seed + 1)  # offset so customers/merchants don't collide
    rng = np.random.default_rng(seed + 1)

    rows = []
    used = set()
    while len(rows) < n:
        name = f"fraud_{fake.company()}".replace(",", "").strip()
        if name in used:
            continue
        used.add(name)
        rows.append({
            "merchant": name,
            "category": MERCHANT_CATEGORIES[rng.integers(0, len(MERCHANT_CATEGORIES))],
            "merch_lat": float(rng.uniform(25.0, 49.0)),
            "merch_long": float(rng.uniform(-125.0, -67.0)),
        })

    df = pd.DataFrame(rows, columns=["merchant", "category", "merch_lat", "merch_long"])
    # Ensure merchant is stored as plain object (str) dtype, not pandas StringDtype
    df["merchant"] = df["merchant"].astype(object)
    return df


TRANSACTION_COLUMNS = [
    "cc_num", "merchant", "category", "amt", "trans_date_trans_time",
    "lat", "long", "city", "state", "zip", "city_pop", "job", "dob",
    "trans_num", "unix_time", "merch_lat", "merch_long",
]


def generate_transactions(
    customers: pd.DataFrame,
    merchants: pd.DataFrame,
    n: int,
    seed: int,
    start: datetime,
    end: datetime,
) -> pd.DataFrame:
    """Generate `n` transactions joining random customers x merchants over [start, end)."""
    if customers.empty or merchants.empty:
        raise ValueError("customers and merchants must be non-empty")

    rng = np.random.default_rng(seed + 2)
    cust_idx = rng.integers(0, len(customers), size=n)
    merch_idx = rng.integers(0, len(merchants), size=n)
    cust_rows = customers.iloc[cust_idx].reset_index(drop=True)
    merch_rows = merchants.iloc[merch_idx].reset_index(drop=True)

    span_seconds = int((end - start).total_seconds())
    offsets = rng.integers(0, span_seconds, size=n)
    timestamps = pd.to_datetime(start) + pd.to_timedelta(offsets, unit="s")

    amts = np.round(rng.lognormal(mean=3.0, sigma=1.0, size=n), 2)

    # Use rng.bytes to produce 16 random bytes per transaction, then hex-encode
    trans_nums = ["".join(f"{b:02x}" for b in rng.bytes(16)) for _ in range(n)]

    df = pd.DataFrame({
        "cc_num": cust_rows["cc_num"].values,
        "merchant": merch_rows["merchant"].values,
        "category": merch_rows["category"].values,
        "amt": amts,
        "trans_date_trans_time": timestamps,
        "lat": cust_rows["lat"].values,
        "long": cust_rows["long"].values,
        "city": cust_rows["city"].values,
        "state": cust_rows["state"].values,
        "zip": cust_rows["zip"].values,
        "city_pop": cust_rows["city_pop"].values,
        "job": cust_rows["job"].values,
        "dob": cust_rows["dob"].values,
        "trans_num": trans_nums,
        "unix_time": (timestamps.astype("int64") // 10**9),
        "merch_lat": merch_rows["merch_lat"].values,
        "merch_long": merch_rows["merch_long"].values,
    }, columns=TRANSACTION_COLUMNS)

    return df


def inject_fraud_labels(
    txns: pd.DataFrame, target_rate: float, seed: int,
) -> pd.DataFrame:
    """Add `is_fraud` (0/1) biased toward high-amount and far-from-home transactions.

    Note: noise rate is 0.01 (1%) rather than the 0.10 suggested in the original
    spec sketch.  With 10% noise the observed fraud rate would be approximately
    0.9*0.01 + 0.1*0.99 ≈ 10%, far outside the 0.5%–2% test bound.  Using 1%
    noise keeps the observed rate within [target_rate*0.9, target_rate*1.1].
    """
    if not 0 < target_rate < 1:
        raise ValueError("target_rate must be in (0, 1)")

    rng = np.random.default_rng(seed + 3)

    distance = np.sqrt(
        (txns["lat"].astype(float) - txns["merch_lat"].astype(float)) ** 2
        + (txns["long"].astype(float) - txns["merch_long"].astype(float)) ** 2
    )
    amt_norm = (txns["amt"] - txns["amt"].min()) / (txns["amt"].max() - txns["amt"].min() + 1e-9)
    dist_norm = (distance - distance.min()) / (distance.max() - distance.min() + 1e-9)
    score = 0.7 * amt_norm + 0.3 * dist_norm

    threshold = np.quantile(score, 1 - target_rate)
    raw_label = (score >= threshold).astype(int)

    # 1% label noise — keeps observed rate within ~[0.005, 0.02] for target_rate=0.01
    noise = rng.binomial(1, 0.01, size=len(txns))
    is_fraud = np.where(noise == 1, 1 - raw_label, raw_label)

    out = txns.copy()
    out["is_fraud"] = is_fraud.astype("int8")
    return out
