-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Cleanup legacy artifacts (M2c)
-- MAGIC
-- MAGIC Drops the silver_silver schema that was created in M2b before the
-- MAGIC dbt/macros/generate_schema_name.sql override was added. Cosmetic only —
-- MAGIC the correct silver schema is unaffected.

-- COMMAND ----------

DROP SCHEMA IF EXISTS northwind_payments.silver_silver CASCADE;

-- COMMAND ----------

SELECT schema_name
FROM system.information_schema.schemata
WHERE catalog_name = 'northwind_payments'
ORDER BY schema_name;
