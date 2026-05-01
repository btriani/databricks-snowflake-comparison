{{ config(
    materialized='view',
    schema='silver',
    alias='customers'
) }}

SELECT
    {{ dbt_utils.generate_surrogate_key(['cc_num']) }} AS customer_sk,
    cc_num,
    first AS first_name,
    last AS last_name,
    gender,
    street,
    city,
    state,
    zip,
    lat,
    long,
    city_pop,
    job,
    dob,
    dbt_valid_from AS effective_from,
    bronze_ingest_timestamp
FROM {{ ref('customers_snapshot') }}
WHERE dbt_valid_to IS NULL
