#!/usr/bin/env bash
set -euo pipefail

# Deploy the NorthWind fraud-overview Streamlit app to Snowflake.
# Idempotent: snow streamlit deploy --replace re-uploads.

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi

DB="${SNOWFLAKE_DATABASE:-NORTHWIND_PAYMENTS}"
WH="${SNOWFLAKE_WAREHOUSE:-NORTHWIND_WH}"

# Ensure target schema exists
snow sql -q "USE WAREHOUSE $WH; USE DATABASE $DB; CREATE SCHEMA IF NOT EXISTS APPS COMMENT = 'Streamlit-in-Snowflake apps';" --format json > /tmp/snowflake_apps_schema.json

echo "[deploy-streamlit] deploying northwind_fraud_overview to $DB.APPS..."
(cd snowflake/streamlit && snow streamlit deploy --replace 2>&1 | tail -10)

echo "[deploy-streamlit] app URL:"
snow streamlit get-url northwind_fraud_overview --database "$DB" --schema APPS 2>&1 | tail -3
echo "[deploy-streamlit] done."
