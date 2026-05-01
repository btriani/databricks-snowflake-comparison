{{ config(
    materialized='table',
    schema='gold',
    alias='kpi_executive'
) }}

WITH per_day AS (
    SELECT
        DATE(trans_date_trans_time) AS trans_date,
        COUNT(*) AS total_txn,
        SUM(amt) AS total_amt_processed,
        SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_txn,
        SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) AS fraud_amt_processed
    FROM {{ ref('silver_transactions') }}
    GROUP BY DATE(trans_date_trans_time)
),

ranked_merchants AS (
    SELECT
        DATE(t.trans_date_trans_time) AS trans_date,
        m.merchant_name,
        SUM(CASE WHEN t.is_fraud = 1 THEN t.amt ELSE 0 END) AS fraud_amt,
        ROW_NUMBER() OVER (
            PARTITION BY DATE(t.trans_date_trans_time)
            ORDER BY SUM(CASE WHEN t.is_fraud = 1 THEN t.amt ELSE 0 END) DESC
        ) AS rn
    FROM {{ ref('silver_transactions') }} t
    INNER JOIN {{ ref('silver_merchants') }} m ON m.merchant_sk = t.merchant_sk
    GROUP BY DATE(t.trans_date_trans_time), m.merchant_name
),

top3_merchants AS (
    SELECT
        trans_date,
        ARRAY_AGG(merchant_name) AS top3_risky_merchants
    FROM ranked_merchants
    WHERE rn <= 3
    GROUP BY trans_date
)

SELECT
    p.trans_date,
    p.total_txn,
    p.total_amt_processed,
    p.fraud_txn,
    p.fraud_amt_processed,
    CAST(p.fraud_txn AS DOUBLE) / NULLIF(p.total_txn, 0) AS fraud_rate,
    t.top3_risky_merchants
FROM per_day p
LEFT JOIN top3_merchants t ON t.trans_date = p.trans_date
ORDER BY p.trans_date
