{{ config(
    materialized='table',
    schema='_quarantine',
    alias='transactions_orphan_cc_num'
) }}

WITH bronze_dedup AS (
    SELECT
        trans_num,
        cc_num,
        COALESCE(amt, transaction_amount) AS amt_str,
        trans_date_trans_time,
        is_fraud,
        _ingest_timestamp,
        _source_file
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY trans_num ORDER BY _ingest_timestamp DESC) AS rn
        FROM {{ source('bronze', 'transactions') }}
        WHERE trans_num IS NOT NULL
    )
    WHERE rn = 1
)

SELECT
    b.trans_num,
    b.cc_num,
    b.amt_str,
    b.trans_date_trans_time,
    b.is_fraud,
    b._ingest_timestamp AS bronze_ingest_timestamp,
    b._source_file AS bronze_source_file,
    'orphan_cc_num' AS quarantine_reason
FROM bronze_dedup b
LEFT JOIN {{ ref('silver_customers') }} c ON c.cc_num = b.cc_num
WHERE c.cc_num IS NULL
