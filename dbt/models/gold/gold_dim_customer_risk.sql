{{ config(
    materialized='table',
    schema='gold',
    alias='dim_customer_risk'
) }}

WITH per_customer AS (
    SELECT
        c.customer_sk,
        c.cc_num,
        c.first_name,
        c.last_name,
        c.state,
        SUM(CASE WHEN t.is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_txn_count,
        SUM(t.amt) AS total_spend,
        COUNT(DISTINCT m.merchant_sk) AS distinct_merchants,
        COUNT(DISTINCT c2.state) AS distinct_states_visited
    FROM {{ ref('silver_customers') }} c
    LEFT JOIN {{ ref('silver_transactions') }} t ON t.customer_sk = c.customer_sk
    LEFT JOIN {{ ref('silver_merchants') }} m ON m.merchant_sk = t.merchant_sk
    LEFT JOIN {{ ref('silver_customers') }} c2 ON c2.customer_sk = t.customer_sk
    GROUP BY c.customer_sk, c.cc_num, c.first_name, c.last_name, c.state
)

SELECT
    customer_sk,
    cc_num,
    first_name,
    last_name,
    state,
    COALESCE(fraud_txn_count, 0) AS fraud_txn_count,
    COALESCE(total_spend, 0) AS total_spend,
    COALESCE(distinct_merchants, 0) AS distinct_merchants,
    COALESCE(distinct_states_visited, 0) AS distinct_states_visited,
    LEAST(100, (
        CASE WHEN COALESCE(fraud_txn_count, 0) > 0 THEN 40 ELSE 0 END
        + LEAST(30, COALESCE(total_spend, 0) / 100.0 * 0.5)
        + LEAST(30, COALESCE(distinct_states_visited, 0) * 1.0)
    )) AS risk_score
FROM per_customer
