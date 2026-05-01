-- M2a bronze sanity checks. Run after `make ingest-databricks`.

-- 1. All four bronze tables exist with the expected tags
SELECT table_name, tag_name, tag_value
FROM system.information_schema.table_tags
WHERE catalog_name = 'northwind_payments'
  AND schema_name = 'bronze'
  AND table_name IN ('transactions', 'customers', 'merchants', 'banks')
ORDER BY table_name, tag_name;

-- 2. Row counts in expected ranges (default `make generate` produces 100K txns / 5K customers / 500 merchants)
SELECT
    'transactions' AS tbl,
    COUNT(*) AS rows,
    SUM(CASE WHEN amt IS NULL THEN 1 ELSE 0 END) AS amt_null,
    SUM(CASE WHEN transaction_amount IS NULL THEN 1 ELSE 0 END) AS txn_amount_null
FROM northwind_payments.bronze.transactions
UNION ALL
SELECT 'customers',  COUNT(*), NULL, NULL FROM northwind_payments.bronze.customers
UNION ALL
SELECT 'merchants',  COUNT(*), NULL, NULL FROM northwind_payments.bronze.merchants
UNION ALL
SELECT 'banks',      COUNT(*), NULL, NULL FROM northwind_payments.bronze.banks;

-- 3. Both v1 and v2 schema columns present in transactions (proves schema evolution worked)
SELECT column_name, data_type
FROM system.information_schema.columns
WHERE table_catalog = 'northwind_payments'
  AND table_schema = 'bronze'
  AND table_name = 'transactions'
  AND column_name IN ('amt', 'transaction_amount', 'device_id', 'cc_num', 'is_fraud',
                      '_ingest_timestamp', '_source_file')
ORDER BY column_name;

-- 4. Per-source-file row counts (verifies all 4 transaction parquet files landed)
SELECT
    REGEXP_EXTRACT(_source_file, 'transactions_(v[12]_(?:current|late))', 1) AS source_kind,
    COUNT(*) AS rows
FROM northwind_payments.bronze.transactions
GROUP BY 1
ORDER BY 1;
