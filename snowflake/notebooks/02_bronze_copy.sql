-- Bronze ingest: COPY INTO from @NORTHWIND_LANDING.
-- Truncate-and-reload — bronze should reflect what's currently on the stage.
-- ON_ERROR=CONTINUE keeps the deliberate-dirt rows flowing — silver handles them.

USE WAREHOUSE NORTHWIND_WH;
USE DATABASE NORTHWIND_PAYMENTS;
USE SCHEMA BRONZE;

TRUNCATE TABLE TRANSACTIONS;
TRUNCATE TABLE CUSTOMERS;
TRUNCATE TABLE MERCHANTS;
TRUNCATE TABLE BANKS;

-- 1. Transactions v1 (has amt, no device_id, no transaction_amount)
COPY INTO TRANSACTIONS (
    cc_num, merchant, category, amt,
    trans_date_trans_time, lat, long, merch_lat, merch_long,
    trans_num, unix_time, is_fraud,
    _ingest_timestamp, _source_file
)
FROM (
    SELECT
        $1:cc_num::STRING,
        $1:merchant::STRING,
        $1:category::STRING,
        $1:amt::STRING,
        $1:trans_date_trans_time::STRING,
        $1:lat::STRING,
        $1:long::STRING,
        $1:merch_lat::STRING,
        $1:merch_long::STRING,
        $1:trans_num::STRING,
        $1:unix_time::STRING,
        $1:is_fraud::NUMBER,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        METADATA$FILENAME
    FROM @NORTHWIND_LANDING (FILE_FORMAT => 'PARQUET_FORMAT')
)
PATTERN = '.*transactions_v1_.*\.parquet'
ON_ERROR = CONTINUE
FORCE = TRUE;

-- 2. Transactions v2 (has device_id and transaction_amount instead of amt)
COPY INTO TRANSACTIONS (
    cc_num, merchant, category, transaction_amount, device_id,
    trans_date_trans_time, lat, long, merch_lat, merch_long,
    trans_num, unix_time, is_fraud,
    _ingest_timestamp, _source_file
)
FROM (
    SELECT
        $1:cc_num::STRING,
        $1:merchant::STRING,
        $1:category::STRING,
        $1:transaction_amount::STRING,
        $1:device_id::STRING,
        $1:trans_date_trans_time::STRING,
        $1:lat::STRING,
        $1:long::STRING,
        $1:merch_lat::STRING,
        $1:merch_long::STRING,
        $1:trans_num::STRING,
        $1:unix_time::STRING,
        $1:is_fraud::NUMBER,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        METADATA$FILENAME
    FROM @NORTHWIND_LANDING (FILE_FORMAT => 'PARQUET_FORMAT')
)
PATTERN = '.*transactions_v2_.*\.parquet'
ON_ERROR = CONTINUE
FORCE = TRUE;

-- 3. Customers
COPY INTO CUSTOMERS (
    cc_num, first, last, gender, street, city, state, zip, lat, long,
    city_pop, job, dob, _ingest_timestamp, _source_file
)
FROM (
    SELECT
        $1:cc_num::STRING,
        $1:first::STRING,
        $1:last::STRING,
        $1:gender::STRING,
        $1:street::STRING,
        $1:city::STRING,
        $1:state::STRING,
        $1:zip::STRING,
        $1:lat::STRING,
        $1:long::STRING,
        $1:city_pop::NUMBER,
        $1:job::STRING,
        $1:dob::STRING,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        METADATA$FILENAME
    FROM @NORTHWIND_LANDING (FILE_FORMAT => 'PARQUET_FORMAT')
)
PATTERN = '.*customers\.parquet'
ON_ERROR = CONTINUE
FORCE = TRUE;

-- 4. Merchants
COPY INTO MERCHANTS (
    merchant, category, merch_lat, merch_long, _ingest_timestamp, _source_file
)
FROM (
    SELECT
        $1:merchant::STRING,
        $1:category::STRING,
        $1:merch_lat::STRING,
        $1:merch_long::STRING,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        METADATA$FILENAME
    FROM @NORTHWIND_LANDING (FILE_FORMAT => 'PARQUET_FORMAT')
)
PATTERN = '.*merchants\.parquet'
ON_ERROR = CONTINUE
FORCE = TRUE;

-- 5. Banks
COPY INTO BANKS (
    rssd_id, bank_name, city, state, charter_class, primary_federal_regulator,
    _ingest_timestamp, _source_file
)
FROM (
    SELECT
        $1:rssd_id::NUMBER,
        $1:bank_name::STRING,
        $1:city::STRING,
        $1:state::STRING,
        $1:charter_class::STRING,
        $1:primary_federal_regulator::STRING,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        METADATA$FILENAME
    FROM @NORTHWIND_LANDING (FILE_FORMAT => 'PARQUET_FORMAT')
)
PATTERN = '.*banks\.parquet'
ON_ERROR = CONTINUE
FORCE = TRUE;

-- Sanity check
SELECT 'transactions' AS tbl, COUNT(*) AS n FROM TRANSACTIONS
UNION ALL SELECT 'customers',  COUNT(*) FROM CUSTOMERS
UNION ALL SELECT 'merchants',  COUNT(*) FROM MERCHANTS
UNION ALL SELECT 'banks',      COUNT(*) FROM BANKS;
