#!/usr/bin/env bash
set -euo pipefail

# Snowflake preflight: render ~/.snowflake/config.toml from .env and verify creds.
# Mirrors scripts/databricks_preflight.sh.
#
# snowflake-cli is installed via `uv tool install snowflake-cli` (NOT in pyproject.toml)
# because its click==8.1.8 pin conflicts with dbt-core>=1.11.8.

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi

: "${SNOWFLAKE_ACCOUNT:?SNOWFLAKE_ACCOUNT not set in .env — see .env.example}"
: "${SNOWFLAKE_USER:?SNOWFLAKE_USER not set in .env}"
: "${SNOWFLAKE_PASSWORD:?SNOWFLAKE_PASSWORD not set in .env (PAT goes here)}"
: "${SNOWFLAKE_ROLE:=ACCOUNTADMIN}"
: "${SNOWFLAKE_WAREHOUSE:=COMPUTE_WH}"

if ! command -v snow >/dev/null 2>&1; then
    echo "[preflight] 'snow' CLI not on PATH. Install with: uv tool install snowflake-cli"
    echo "[preflight] then ensure ~/.local/bin is on PATH."
    exit 1
fi

mkdir -p "$HOME/.snowflake"
CONFIG="$HOME/.snowflake/config.toml"

cat > "$CONFIG" <<EOF
default_connection_name = "northwind"

[connections.northwind]
account = "$SNOWFLAKE_ACCOUNT"
user = "$SNOWFLAKE_USER"
password = "$SNOWFLAKE_PASSWORD"
role = "$SNOWFLAKE_ROLE"
warehouse = "$SNOWFLAKE_WAREHOUSE"
EOF
chmod 600 "$CONFIG"

echo "[preflight] wrote $CONFIG (connection 'northwind', auth=PAT)"
echo "[preflight] verifying credentials..."
snow sql -q "SELECT CURRENT_USER(), CURRENT_ACCOUNT(), CURRENT_ROLE(), CURRENT_REGION()" --format json 2>&1 | head -20

echo "[preflight] existing warehouses:"
snow sql -q "SHOW WAREHOUSES" --format json 2>&1 | python3 -c "
import json, sys
try:
    rows = json.load(sys.stdin)
    if isinstance(rows, list):
        for r in rows:
            print(f\"  - {r.get('name')} (size={r.get('size','?')}, state={r.get('state','?')})\")
except Exception as e:
    print(f'  (could not parse: {e})', file=sys.stderr)
"

echo "[preflight] done."
