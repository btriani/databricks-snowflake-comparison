{{ config(
    materialized='table',
    schema='silver',
    alias='transactions'
) }}

WITH bronze_typed AS (
    SELECT
        cc_num,
        merchant,
        category,
        COALESCE(amt, transaction_amount) AS amt_str,
        device_id,
        trans_date_trans_time,
        CAST(lat AS DOUBLE) AS lat,
        CAST(long AS DOUBLE) AS long,
        merch_lat,
        merch_long,
        trans_num,
        unix_time,
        is_fraud,
        _ingest_timestamp,
        _source_file,
        CASE
            WHEN _source_file LIKE '%transactions_v1_%' THEN 'v1'
            WHEN _source_file LIKE '%transactions_v2_%' THEN 'v2'
            ELSE 'unknown'
        END AS source_schema_version
    FROM {{ source('bronze', 'transactions') }}
    WHERE trans_num IS NOT NULL
),

dedup AS (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY trans_num
                ORDER BY _ingest_timestamp DESC
            ) AS rn
        FROM bronze_typed
    )
    WHERE rn = 1
),

amt_parsed AS (
    SELECT
        *,
        TRY_CAST(REPLACE(REPLACE(amt_str, '$', ''), ',', '') AS DECIMAL(12, 2)) AS amt
    FROM dedup
),

valid_amt AS (
    SELECT *
    FROM amt_parsed
    WHERE amt IS NOT NULL AND amt > 0
),

joined AS (
    SELECT
        v.trans_num,
        v.cc_num,
        c.customer_sk,
        m.merchant_sk,
        v.merchant AS merchant_name,
        v.category,
        v.amt,
        v.trans_date_trans_time,
        v.unix_time,
        v.lat AS customer_lat,
        v.long AS customer_long,
        CAST(v.merch_lat AS DOUBLE) AS merch_lat,
        CAST(v.merch_long AS DOUBLE) AS merch_long,
        v.is_fraud,
        v.device_id,
        v.source_schema_version,
        v._ingest_timestamp AS bronze_ingest_timestamp,
        v._source_file AS bronze_source_file
    FROM valid_amt v
    INNER JOIN {{ ref('silver_customers') }} c ON c.cc_num = v.cc_num
    LEFT JOIN  {{ ref('silver_merchants') }} m ON m.merchant_name = v.merchant
)

SELECT * FROM joined
