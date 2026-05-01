{{ config(
    materialized='table',
    schema='gold',
    alias='fct_fraud_daily'
) }}

WITH base AS (
    SELECT
        DATE(t.trans_date_trans_time) AS trans_date,
        m.category AS merchant_category,
        c.state AS customer_state,
        t.amt,
        t.is_fraud
    FROM {{ ref('silver_transactions') }} t
    INNER JOIN {{ ref('silver_customers') }} c ON c.customer_sk = t.customer_sk
    LEFT JOIN  {{ ref('silver_merchants') }} m ON m.merchant_sk = t.merchant_sk
)

SELECT
    trans_date,
    merchant_category,
    customer_state,
    COUNT(*) AS txn_count,
    SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_count,
    CAST(SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS DOUBLE) /
        NULLIF(COUNT(*), 0) AS fraud_rate,
    SUM(amt) AS total_amt,
    SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) AS fraud_amt
FROM base
GROUP BY trans_date, merchant_category, customer_state
