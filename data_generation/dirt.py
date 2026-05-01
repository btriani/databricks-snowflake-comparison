"""Deliberate-dirt injection for the bronze landing layer.

Each function takes a clean DataFrame and returns a dirtied copy. The dirt
modes mirror the spec's "Deliberate dirt injected into bronze" section.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def inject_nulls(
    df: pd.DataFrame, columns: list[str], rate: float, seed: int,
) -> pd.DataFrame:
    """Set `rate` fraction of values in each named column to NaN."""
    missing = [c for c in columns if c not in df.columns]
    if missing:
        raise KeyError(f"columns not in DataFrame: {missing}")

    rng = np.random.default_rng(seed)
    out = df.copy()
    for col in columns:
        mask = rng.random(len(out)) < rate
        out.loc[mask, col] = np.nan
    return out


def inject_duplicates(df: pd.DataFrame, rate: float, seed: int) -> pd.DataFrame:
    """Append byte-identical duplicates of `rate` fraction of rows. Order is shuffled."""
    rng = np.random.default_rng(seed)
    n_dup = int(len(df) * rate)
    if n_dup == 0:
        return df.copy()
    dup_idx = rng.integers(0, len(df), size=n_dup)
    duplicates = df.iloc[dup_idx]
    out = pd.concat([df, duplicates], ignore_index=True)
    out = out.sample(frac=1.0, random_state=seed).reset_index(drop=True)
    return out


def split_late_arrivers(
    df: pd.DataFrame,
    late_rate: float,
    max_lateness_days: int,
    seed: int,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Split into (current, late). Late rows get timestamps shifted backward by 1..max_lateness_days days."""
    rng = np.random.default_rng(seed)
    is_late = rng.random(len(df)) < late_rate
    current = df.loc[~is_late].reset_index(drop=True)
    late = df.loc[is_late].reset_index(drop=True).copy()

    if len(late):
        days_back = rng.integers(1, max_lateness_days + 1, size=len(late))
        late["trans_date_trans_time"] = (
            pd.to_datetime(late["trans_date_trans_time"])
            - pd.to_timedelta(days_back, unit="D")
        )
    return current, late


def to_v2_schema(df: pd.DataFrame, seed: int) -> pd.DataFrame:
    """Return df with amt renamed to transaction_amount and a synthetic device_id added."""
    rng = np.random.default_rng(seed)
    out = df.rename(columns={"amt": "transaction_amount"}).copy()
    out["device_id"] = [
        f"dev_{int(x):010x}" for x in rng.integers(0, 2**40, size=len(out))
    ]
    out["device_id"] = out["device_id"].astype(object)
    return out


def inject_bad_joins(
    df: pd.DataFrame, valid_cc_nums: set[str], rate: float, seed: int,
) -> pd.DataFrame:
    """Replace `rate` fraction of cc_num values with random 16-digit strings not in valid_cc_nums."""
    if rate == 0:
        return df.copy()
    rng = np.random.default_rng(seed)
    out = df.copy()
    mask = rng.random(len(out)) < rate
    n_replace = int(mask.sum())
    if n_replace == 0:
        return out
    fakes = []
    while len(fakes) < n_replace:
        candidate = "".join(str(d) for d in rng.integers(0, 10, size=16))
        if candidate not in valid_cc_nums:
            fakes.append(candidate)
    out.loc[mask, "cc_num"] = fakes
    return out


def inject_type_drift(
    df: pd.DataFrame, column: str, rate: float, seed: int,
) -> pd.DataFrame:
    """Cast `rate` fraction of column values to strings formatted as `$1,234.56`."""
    if column not in df.columns:
        raise KeyError(column)
    rng = np.random.default_rng(seed)
    out = df.copy()
    out[column] = out[column].astype(object)
    mask = rng.random(len(out)) < rate
    out.loc[mask, column] = out.loc[mask, column].map(
        lambda v: f"${float(v):,.2f}"
    )
    return out


def apply_all_dirt(
    txns: pd.DataFrame,
    valid_cc_nums: set[str],
    seed: int,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Apply every dirt mode and split into (v1_current, v1_late, v2_current, v2_late).

    Defaults from the spec:
        - nulls: 0.005 in cc_num and amt
        - duplicates: 0.01 of trans_num
        - late: 0.05 of rows shifted up to 3 days back
        - bad joins: 0.02 of cc_num
        - type drift: 0.01 of amt
        - schema evolution: half the rows get the v2 schema
    """
    after_nulls = inject_nulls(txns, columns=["cc_num", "amt"], rate=0.005, seed=seed)
    after_dupes = inject_duplicates(after_nulls, rate=0.01, seed=seed + 1)
    after_bad = inject_bad_joins(after_dupes, valid_cc_nums=valid_cc_nums, rate=0.02, seed=seed + 2)
    after_drift = inject_type_drift(after_bad, column="amt", rate=0.01, seed=seed + 3)

    midpoint = len(after_drift) // 2
    v1_part = after_drift.iloc[:midpoint].reset_index(drop=True)
    v2_part = after_drift.iloc[midpoint:].reset_index(drop=True)
    v2_part = to_v2_schema(v2_part, seed=seed + 4)

    v1_current, v1_late = split_late_arrivers(
        v1_part, late_rate=0.05, max_lateness_days=3, seed=seed + 5,
    )
    v2_current, v2_late = split_late_arrivers(
        v2_part, late_rate=0.05, max_lateness_days=3, seed=seed + 6,
    )
    return v1_current, v1_late, v2_current, v2_late
