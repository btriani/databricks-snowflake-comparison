-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Load bronze.banks (FFIEC reference) — M2a
-- MAGIC
-- MAGIC One-shot COPY INTO from the Volume's reference/ folder. Banks are small and
-- MAGIC rarely change; Auto Loader is overkill. Re-runs are idempotent because
-- MAGIC COPY INTO tracks loaded files; we use `force = 'true'` to allow re-loads.

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS northwind_payments.bronze.banks (
    rssd_id BIGINT,
    bank_name STRING,
    city STRING,
    state STRING,
    charter_class STRING,
    primary_federal_regulator STRING,
    _ingest_timestamp TIMESTAMP,
    _source_file STRING
) USING DELTA
COMMENT 'FFIEC institution reference data. Reloaded each ingest run via COPY INTO.';

-- COMMAND ----------

COPY INTO northwind_payments.bronze.banks
FROM (
    SELECT
        rssd_id,
        bank_name,
        city,
        state,
        charter_class,
        primary_federal_regulator,
        current_timestamp() AS _ingest_timestamp,
        _metadata.file_path AS _source_file
    FROM '/Volumes/northwind_payments/bronze/landing/reference/'
)
FILEFORMAT = PARQUET
COPY_OPTIONS ('mergeSchema' = 'true', 'force' = 'true');

-- COMMAND ----------

SELECT COUNT(*) AS bank_row_count, MAX(_ingest_timestamp) AS last_load FROM northwind_payments.bronze.banks;
