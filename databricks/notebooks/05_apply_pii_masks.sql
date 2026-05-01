-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Apply PII column masks (M2c)
-- MAGIC
-- MAGIC Binds masking functions from northwind_payments.security to the PII columns
-- MAGIC of silver.customers_snapshot (where the physical data lives) and
-- MAGIC silver.transactions (which carries cc_num denormalized).
-- MAGIC
-- MAGIC Idempotent. Re-runnable after every `dbt build` (table-materialized models
-- MAGIC drop column masks on rebuild).

-- COMMAND ----------

ALTER TABLE northwind_payments.silver.customers_snapshot
ALTER COLUMN cc_num SET MASK northwind_payments.security.mask_cc_num;

ALTER TABLE northwind_payments.silver.customers_snapshot
ALTER COLUMN first SET MASK northwind_payments.security.mask_name;

ALTER TABLE northwind_payments.silver.customers_snapshot
ALTER COLUMN last SET MASK northwind_payments.security.mask_name;

ALTER TABLE northwind_payments.silver.customers_snapshot
ALTER COLUMN street SET MASK northwind_payments.security.mask_address;

ALTER TABLE northwind_payments.silver.customers_snapshot
ALTER COLUMN dob SET MASK northwind_payments.security.mask_dob;

-- COMMAND ----------

ALTER TABLE northwind_payments.silver.transactions
ALTER COLUMN cc_num SET MASK northwind_payments.security.mask_cc_num;

-- COMMAND ----------

SELECT
    table_name,
    column_name,
    mask_name
FROM system.information_schema.column_masks
WHERE table_catalog = 'northwind_payments'
  AND table_schema = 'silver'
ORDER BY table_name, column_name;
