-- Databricks notebook source
-- MAGIC %md
-- MAGIC # NorthWind Payments — UC Setup (M2a)
-- MAGIC
-- MAGIC Idempotent setup of the catalog, schemas, tags, and the bronze landing Volume.
-- MAGIC Run via `bash scripts/setup_uc.sh` (preferred) or by importing this notebook
-- MAGIC into the workspace and clicking Run All.

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS northwind_payments
COMMENT 'NorthWind Payments lakehouse — fictional fintech portfolio project';

ALTER CATALOG northwind_payments SET TAGS ('project' = 'northwind-payments', 'milestone' = 'm2a');

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS northwind_payments.bronze
COMMENT 'Raw landing tables. Schema-on-read. Dirt preserved.';

CREATE SCHEMA IF NOT EXISTS northwind_payments._quarantine
COMMENT 'Rows rejected by silver layer (M2b). Empty in M2a.';

ALTER SCHEMA northwind_payments.bronze SET TAGS ('project' = 'northwind-payments');
ALTER SCHEMA northwind_payments._quarantine SET TAGS ('project' = 'northwind-payments');

-- COMMAND ----------

CREATE VOLUME IF NOT EXISTS northwind_payments.bronze.landing
COMMENT 'Drop point for parquet files generated locally by `npl-generate`.';

-- COMMAND ----------

SELECT 'catalog' AS object_type, catalog_name AS name FROM system.information_schema.catalogs WHERE catalog_name = 'northwind_payments'
UNION ALL
SELECT 'schema', CONCAT(catalog_name, '.', schema_name) FROM system.information_schema.schemata
  WHERE catalog_name = 'northwind_payments'
UNION ALL
SELECT 'volume', CONCAT(volume_catalog, '.', volume_schema, '.', volume_name) FROM system.information_schema.volumes
  WHERE volume_catalog = 'northwind_payments';
