#!/usr/bin/env bash
set -euo pipefail

# Run Snowflake cost-tracking SQL. ACCOUNT_USAGE has 45min-3hr lag — fresh runs may not show.

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi

echo "[validate-cost-snowflake] querying SNOWFLAKE.ACCOUNT_USAGE..."
snow sql -f snowflake/notebooks/cost_tracking.sql --format json 2>&1 | tail -30
echo "[validate-cost-snowflake] done. (Lag note: 45min-3hr; recent runs may be invisible.)"
