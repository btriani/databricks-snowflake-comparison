-- NorthWind Payments — Snowflake setup (M3)
-- Idempotent. Re-runnable. Owned by ACCOUNTADMIN.

-- 1. Warehouse — XS, 60s auto-suspend (cost guardrail)
CREATE WAREHOUSE IF NOT EXISTS NORTHWIND_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'NorthWind Payments project warehouse — XS, 60s auto-suspend';

USE WAREHOUSE NORTHWIND_WH;

-- 2. Database + schemas (mirror Databricks layout)
CREATE DATABASE IF NOT EXISTS NORTHWIND_PAYMENTS
    COMMENT = 'NorthWind Payments lakehouse — Snowflake mirror of Databricks side';

USE DATABASE NORTHWIND_PAYMENTS;

CREATE SCHEMA IF NOT EXISTS BRONZE      COMMENT = 'Raw landing tables, schema-on-read';
CREATE SCHEMA IF NOT EXISTS SILVER      COMMENT = 'Cleansed, conformed, joined';
CREATE SCHEMA IF NOT EXISTS GOLD        COMMENT = 'BI-ready aggregates and KPIs';
CREATE SCHEMA IF NOT EXISTS SECURITY    COMMENT = 'Masking policies, tags';
CREATE SCHEMA IF NOT EXISTS _QUARANTINE COMMENT = 'Rows that fail silver checks';

-- 3. File format for parquet ingestion
CREATE FILE FORMAT IF NOT EXISTS NORTHWIND_PAYMENTS.BRONZE.PARQUET_FORMAT
    TYPE = PARQUET
    COMPRESSION = AUTO
    USE_LOGICAL_TYPE = TRUE
    COMMENT = 'Default parquet file format for bronze ingestion';

-- 4. Internal named stage for bronze landing files
CREATE STAGE IF NOT EXISTS NORTHWIND_PAYMENTS.BRONZE.NORTHWIND_LANDING
    FILE_FORMAT = (FORMAT_NAME = NORTHWIND_PAYMENTS.BRONZE.PARQUET_FORMAT)
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Internal stage for parquet files from data_generation/cli.py';

-- 5. Custom role for PII access (analog of npl_pii_reader on Databricks)
CREATE ROLE IF NOT EXISTS NPL_PII_READER
    COMMENT = 'Members can see unmasked PII columns; non-members see masked';

-- 6. Project tag for cost telemetry attribution
CREATE TAG IF NOT EXISTS NORTHWIND_PAYMENTS.SECURITY.PROJECT_TAG
    COMMENT = 'Identifies resources owned by the northwind-payments project';

-- 7. Tag the warehouse so ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY is filterable
ALTER WAREHOUSE NORTHWIND_WH SET TAG NORTHWIND_PAYMENTS.SECURITY.PROJECT_TAG = 'northwind-payments';

-- 8. Bronze tables — declared explicitly so dbt sources resolve.
--    amt/transaction_amount stay STRING per M1 finding #1 (parquet has uniform string type).
CREATE TABLE IF NOT EXISTS NORTHWIND_PAYMENTS.BRONZE.TRANSACTIONS (
    cc_num                STRING,
    merchant              STRING,
    category              STRING,
    amt                   STRING,
    transaction_amount    STRING,
    device_id             STRING,
    trans_date_trans_time STRING,
    lat                   STRING,
    long                  STRING,
    merch_lat             STRING,
    merch_long            STRING,
    trans_num             STRING,
    unix_time             STRING,
    is_fraud              NUMBER,
    _ingest_timestamp     TIMESTAMP_NTZ,
    _source_file          STRING
)
COMMENT = 'Bronze transactions — v1+v2 unioned; amt/transaction_amount STRING (M1 finding #1)';

CREATE TABLE IF NOT EXISTS NORTHWIND_PAYMENTS.BRONZE.CUSTOMERS (
    cc_num            STRING,
    first             STRING,
    last              STRING,
    gender            STRING,
    street            STRING,
    city              STRING,
    state             STRING,
    zip               STRING,
    lat               STRING,
    long              STRING,
    city_pop          NUMBER,
    job               STRING,
    dob               STRING,
    _ingest_timestamp TIMESTAMP_NTZ,
    _source_file      STRING
);

CREATE TABLE IF NOT EXISTS NORTHWIND_PAYMENTS.BRONZE.MERCHANTS (
    merchant          STRING,
    category          STRING,
    merch_lat         STRING,
    merch_long        STRING,
    _ingest_timestamp TIMESTAMP_NTZ,
    _source_file      STRING
);

CREATE TABLE IF NOT EXISTS NORTHWIND_PAYMENTS.BRONZE.BANKS (
    rssd_id                   NUMBER,
    bank_name                 STRING,
    city                      STRING,
    state                     STRING,
    charter_class             STRING,
    primary_federal_regulator STRING,
    _ingest_timestamp         TIMESTAMP_NTZ,
    _source_file              STRING
);

-- 9. Print state summary
SHOW WAREHOUSES LIKE 'NORTHWIND_WH';
SHOW SCHEMAS IN DATABASE NORTHWIND_PAYMENTS;
SHOW STAGES IN SCHEMA NORTHWIND_PAYMENTS.BRONZE;
SHOW TABLES IN SCHEMA NORTHWIND_PAYMENTS.BRONZE;
