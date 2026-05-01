#!/usr/bin/env bash
set -euo pipefail

# NorthWind Payments — teardown
#
# Removes all cloud resources created by the project on Databricks and Snowflake,
# plus local generated data. Safe to run any number of times.
#
# Usage:
#     bash scripts/teardown.sh              # all platforms
#     bash scripts/teardown.sh databricks   # one platform only
#     bash scripts/teardown.sh snowflake

TARGET="${1:-all}"

echo "[teardown] target: $TARGET"

if [[ "$TARGET" == "all" || "$TARGET" == "local" ]]; then
    if [[ -d "data/landing" ]]; then
        echo "[teardown/local] removing data/landing/"
        rm -rf data/landing
    fi
fi

if [[ "$TARGET" == "all" || "$TARGET" == "databricks" ]]; then
    echo "[teardown/databricks] uninstalling bundle and dropping UC catalog..."
    if [[ -f ".env" ]]; then set -a; . .env; set +a; fi

    if [[ -z "${DATABRICKS_HOST:-}" || -z "${DATABRICKS_TOKEN:-}" ]]; then
        echo "[teardown/databricks] DATABRICKS_HOST/TOKEN not set; skipping (assume nothing to clean up)"
    else
        # Delete the AI/BI Lakeview dashboard if we deployed one
        if [[ -f ".dashboard_id" ]]; then
            DASHBOARD_ID=$(cat .dashboard_id)
            echo "[teardown/databricks] deleting Lakeview dashboard $DASHBOARD_ID..."
            databricks api delete "/api/2.0/lakeview/dashboards/$DASHBOARD_ID" 2>/dev/null && \
                rm -f .dashboard_id || \
                echo "[teardown/databricks] dashboard delete failed (may already be gone) — continuing"
        fi

        # Destroy the bundle (removes the deployed job)
        if [[ -d "databricks/bundle" ]]; then
            (cd databricks/bundle && databricks bundle destroy --target dev --auto-approve) 2>/dev/null || \
                echo "[teardown/databricks] bundle destroy failed (perhaps not deployed yet) — continuing"
        fi

        # dbt clean — wipe local target/ and dbt_packages/ caches
        if [[ -d "dbt" ]]; then
            (cd dbt && uv run dbt clean) 2>/dev/null || \
                echo "[teardown/databricks] dbt clean skipped (dbt not initialized?)"
        fi

        # Drop the catalog (CASCADE removes schemas, tables, volumes)
        WAREHOUSE_ID=$(databricks warehouses list --output json 2>/dev/null | python3 -c "
import json, sys
hs = json.load(sys.stdin)
ws = hs if isinstance(hs, list) else hs.get('warehouses', [])
preferred = [w for w in ws if 'starter' in w.get('name','').lower()] or ws
print(preferred[0]['id'] if preferred else '')
")

        if [[ -n "$WAREHOUSE_ID" ]]; then
            echo "[teardown/databricks] dropping catalog northwind_payments via warehouse $WAREHOUSE_ID..."
            BODY=$(printf '{"warehouse_id":"%s","statement":"DROP CATALOG IF EXISTS northwind_payments CASCADE","wait_timeout":"50s"}' "$WAREHOUSE_ID")
            databricks api post /api/2.0/sql/statements --json "$BODY" 2>&1 | head -20 || \
                echo "[teardown/databricks] DROP CATALOG failed (catalog may not exist) — continuing"
        else
            echo "[teardown/databricks] no SQL warehouse available — drop catalog manually in the UI"
        fi
    fi
fi

if [[ "$TARGET" == "all" || "$TARGET" == "snowflake" ]]; then
    echo "[teardown/snowflake] dropping NorthWind objects..."
    if [[ -f ".env" ]]; then set -a; . .env; set +a; fi

    if [[ -z "${SNOWFLAKE_ACCOUNT:-}" ]]; then
        echo "[teardown/snowflake] SNOWFLAKE_ACCOUNT not set — skipping (assume nothing to clean up)"
    else
        snow sql -q "
USE ROLE ACCOUNTADMIN;
DROP STREAMLIT IF EXISTS NORTHWIND_PAYMENTS.APPS.NORTHWIND_FRAUD_OVERVIEW;
DROP DATABASE IF EXISTS NORTHWIND_PAYMENTS CASCADE;
DROP WAREHOUSE IF EXISTS NORTHWIND_WH;
DROP ROLE IF EXISTS NPL_PII_READER;
DROP ROLE IF EXISTS NPL_BI_VIEWER;
" --format json 2>&1 | tail -5 || echo "[teardown/snowflake] some drops failed — continuing"
    fi
fi

echo "[teardown] done"
