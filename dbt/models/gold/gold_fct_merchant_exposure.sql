{{ config(
    materialized='table',
    schema='gold',
    alias='fct_merchant_exposure'
) }}

SELECT
    m.merchant_sk,
    m.merchant_name,
    m.category,
    COUNT(*) AS txn_count,
    SUM(t.amt) AS total_amt,
    SUM(CASE WHEN t.is_fraud = 1 THEN t.amt ELSE 0 END) AS fraud_amt,
    SUM(CASE WHEN t.is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_count,
    CAST(SUM(CASE WHEN t.is_fraud = 1 THEN 1 ELSE 0 END) AS DOUBLE) / NULLIF(COUNT(*), 0) AS fraud_rate
FROM {{ ref('silver_transactions') }} t
INNER JOIN {{ ref('silver_merchants') }} m ON m.merchant_sk = t.merchant_sk
GROUP BY m.merchant_sk, m.merchant_name, m.category
