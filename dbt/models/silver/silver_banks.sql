{{ config(
    materialized='table',
    alias='banks'
) }}

WITH src AS (
    SELECT
        rssd_id,
        TRIM(bank_name) AS bank_name,
        TRIM(city) AS city,
        UPPER(TRIM(state)) AS state,
        TRIM(charter_class) AS charter_class,
        TRIM(primary_federal_regulator) AS primary_federal_regulator,
        _ingest_timestamp AS bronze_ingest_timestamp
    FROM {{ source('bronze', 'banks') }}
)

SELECT * FROM src
