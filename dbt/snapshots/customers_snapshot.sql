{% snapshot customers_snapshot %}

{{
    config(
      target_schema='silver',
      target_database=target.database,
      unique_key='cc_num',
      strategy='check',
      check_cols=['first', 'last', 'gender', 'street', 'city', 'state', 'zip',
                  'lat', 'long', 'city_pop', 'job', 'dob']
    )
}}

WITH deduped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY cc_num
            ORDER BY _ingest_timestamp DESC
        ) AS _rn
    FROM {{ source('bronze', 'customers') }}
    WHERE cc_num IS NOT NULL
)

SELECT
    cc_num,
    first,
    last,
    gender,
    TRIM(street) AS street,
    TRIM(city) AS city,
    UPPER(TRIM(state)) AS state,
    zip,
    CAST(lat AS DOUBLE) AS lat,
    CAST(long AS DOUBLE) AS long,
    CAST(city_pop AS BIGINT) AS city_pop,
    job,
    dob,
    _ingest_timestamp AS bronze_ingest_timestamp
FROM deduped
WHERE _rn = 1

{% endsnapshot %}
