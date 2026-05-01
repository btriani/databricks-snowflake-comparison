{{ config(
    materialized='table',
    schema='silver',
    alias='merchants'
) }}

WITH src AS (
    SELECT
        TRIM(merchant) AS merchant_name,
        category,
        CAST(merch_lat AS DOUBLE) AS merch_lat,
        CAST(merch_long AS DOUBLE) AS merch_long,
        _ingest_timestamp AS bronze_ingest_timestamp
    FROM {{ source('bronze', 'merchants') }}
),

deduped AS (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY merchant_name
                ORDER BY bronze_ingest_timestamp DESC
            ) AS rn
        FROM src
    )
    WHERE rn = 1
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['merchant_name']) }} AS merchant_sk,
    merchant_name,
    category,
    merch_lat,
    merch_long,
    bronze_ingest_timestamp
FROM deduped
