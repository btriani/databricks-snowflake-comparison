-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Security setup (M2c)
-- MAGIC
-- MAGIC Creates `northwind_payments.security` schema with 4 PII masking functions,
-- MAGIC and 3 account groups for least-privilege access.
-- MAGIC
-- MAGIC Idempotent — safe to re-run.

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS northwind_payments.security
COMMENT 'PII masking functions and access-control objects';

ALTER SCHEMA northwind_payments.security SET TAGS ('project' = 'northwind-payments', 'milestone' = 'm2c');

-- COMMAND ----------

CREATE OR REPLACE FUNCTION northwind_payments.security.mask_cc_num(cc STRING)
RETURNS STRING
RETURN CASE
    WHEN is_account_group_member('npl_pii_reader') THEN cc
    WHEN cc IS NULL OR length(cc) < 4 THEN cc
    ELSE concat(repeat('*', length(cc) - 4), substring(cc, length(cc) - 3, 4))
END;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION northwind_payments.security.mask_name(n STRING)
RETURNS STRING
RETURN CASE
    WHEN is_account_group_member('npl_pii_reader') THEN n
    ELSE 'REDACTED'
END;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION northwind_payments.security.mask_address(a STRING)
RETURNS STRING
RETURN CASE
    WHEN is_account_group_member('npl_pii_reader') THEN a
    ELSE 'REDACTED ADDRESS'
END;

-- COMMAND ----------

CREATE OR REPLACE FUNCTION northwind_payments.security.mask_dob(d DATE)
RETURNS DATE
RETURN CASE
    WHEN is_account_group_member('npl_pii_reader') THEN d
    ELSE NULL
END;

-- COMMAND ----------

SELECT routine_name, data_type
FROM system.information_schema.routines
WHERE routine_catalog = 'northwind_payments'
  AND routine_schema = 'security'
ORDER BY routine_name;
