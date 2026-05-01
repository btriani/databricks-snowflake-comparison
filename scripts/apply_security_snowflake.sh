#!/usr/bin/env bash
set -euo pipefail

# Re-apply Snowflake masking policies. Idempotent: CREATE OR REPLACE drops/recreates
# and ALTER TABLE ... SET MASKING POLICY ... FORCE re-binds even if a policy already exists.
# Run after each `dbt build --target snowflake_dev` because table-materialized models
# lose mask bindings on rebuild (M2c finding #7 — same gotcha as Databricks).

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi

snow sql -q "
CREATE ROLE IF NOT EXISTS NPL_PII_READER COMMENT = 'PII unmasked access — see snowflake/notebooks/04_setup_security.sql';
GRANT USAGE ON DATABASE NORTHWIND_PAYMENTS TO ROLE NPL_PII_READER;
GRANT USAGE ON SCHEMA NORTHWIND_PAYMENTS.SILVER TO ROLE NPL_PII_READER;
GRANT USAGE ON SCHEMA NORTHWIND_PAYMENTS.SECURITY TO ROLE NPL_PII_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA NORTHWIND_PAYMENTS.SILVER TO ROLE NPL_PII_READER;
GRANT SELECT ON ALL VIEWS IN SCHEMA NORTHWIND_PAYMENTS.SILVER TO ROLE NPL_PII_READER;
" --format json > /tmp/snowflake_grants.json 2>&1 || echo "[apply-security-snowflake] grants partially failed — continuing"

echo "[apply-security-snowflake] applying masking policies..."
snow sql -f snowflake/notebooks/04_setup_security.sql --format json > /tmp/snowflake_masks.json
echo "[apply-security-snowflake] done."
