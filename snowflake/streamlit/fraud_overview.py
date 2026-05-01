"""NorthWind Payments — Snowflake fraud overview dashboard.

Streamlit-in-Snowflake equivalent of the M2c Lakeview dashboard.
Deployed via `snow streamlit deploy`. Reads from gold tables.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="NorthWind Fraud Overview", layout="wide")
st.title("NorthWind Payments — Fraud Overview")

session = get_active_session()


@st.cache_data(ttl=300)
def kpi_today():
    return session.sql("""
        SELECT trans_date, total_txn, total_amt_processed,
               fraud_txn, fraud_amt_processed, fraud_rate
        FROM NORTHWIND_PAYMENTS.GOLD.KPI_EXECUTIVE
        ORDER BY trans_date DESC
        LIMIT 1
    """).to_pandas()


@st.cache_data(ttl=300)
def fraud_rate_timeseries():
    return session.sql("""
        SELECT trans_date, fraud_rate
        FROM NORTHWIND_PAYMENTS.GOLD.KPI_EXECUTIVE
        ORDER BY trans_date
    """).to_pandas()


@st.cache_data(ttl=300)
def fraud_by_category_state():
    return session.sql("""
        SELECT merchant_category, customer_state,
               AVG(fraud_rate) AS fraud_rate, SUM(txn_count) AS txn_count
        FROM NORTHWIND_PAYMENTS.GOLD.FCT_FRAUD_DAILY
        GROUP BY merchant_category, customer_state
        HAVING SUM(txn_count) >= 10
        ORDER BY fraud_rate DESC
        LIMIT 100
    """).to_pandas()


@st.cache_data(ttl=300)
def top_risk_merchants():
    return session.sql("""
        SELECT merchant_name, category, total_amt, fraud_amt, fraud_rate
        FROM NORTHWIND_PAYMENTS.GOLD.FCT_MERCHANT_EXPOSURE
        ORDER BY fraud_amt DESC
        LIMIT 10
    """).to_pandas()


# Top row: 3 KPI tiles + sparkline
kpi = kpi_today()
ts = fraud_rate_timeseries()

col1, col2, col3 = st.columns(3)
with col1:
    st.metric(
        label="Today's Fraud Rate",
        value=f"{float(kpi['FRAUD_RATE'].iloc[0]) * 100:.2f}%" if not kpi.empty else "—",
    )
with col2:
    val = float(kpi['TOTAL_AMT_PROCESSED'].iloc[0]) if not kpi.empty else 0
    st.metric(
        label="Today's Volume Processed",
        value=f"${val/1000:.1f}K" if val < 1e6 else f"${val/1e6:.2f}M",
    )
with col3:
    st.markdown("**Daily Fraud Rate Trend**")
    if not ts.empty:
        chart_df = ts.rename(columns={"TRANS_DATE": "date", "FRAUD_RATE": "fraud_rate"}).set_index("date")
        st.line_chart(chart_df, height=120)

st.divider()

# Bottom row: 2 detail tables
col4, col5 = st.columns(2)
with col4:
    st.subheader("Fraud Rate by Category × State")
    cat = fraud_by_category_state()
    if not cat.empty:
        cat["FRAUD_RATE"] = cat["FRAUD_RATE"].apply(lambda x: f"{float(x)*100:.2f}%")
        cat["TXN_COUNT"] = cat["TXN_COUNT"].apply(lambda x: f"{int(x):,}")
        st.dataframe(cat, use_container_width=True, hide_index=True)

with col5:
    st.subheader("Top 10 Merchants by Fraud Exposure")
    top = top_risk_merchants()
    if not top.empty:
        top["TOTAL_AMT"] = top["TOTAL_AMT"].apply(lambda x: f"${float(x):,.0f}")
        top["FRAUD_AMT"] = top["FRAUD_AMT"].apply(lambda x: f"${float(x):,.0f}")
        top["FRAUD_RATE"] = top["FRAUD_RATE"].apply(lambda x: f"{float(x)*100:.2f}%")
        st.dataframe(top, use_container_width=True, hide_index=True)

st.caption("Data: NORTHWIND_PAYMENTS.GOLD.* — refreshed via `make dbt-build-snowflake`.")
