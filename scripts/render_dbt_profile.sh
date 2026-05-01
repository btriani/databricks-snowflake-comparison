#!/usr/bin/env bash
set -euo pipefail

# Render ~/.dbt/profiles.yml for the northwind_payments project from .env.
# Idempotent. Overwrites any existing northwind_payments profile entry.

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi
: "${DATABRICKS_HOST:?see scripts/databricks_preflight.sh}"
: "${DATABRICKS_TOKEN:?see scripts/databricks_preflight.sh}"

WAREHOUSE_ID=$(databricks warehouses list --output json | python3 -c "
import json, sys
hs = json.load(sys.stdin)
ws = hs if isinstance(hs, list) else hs.get('warehouses', [])
preferred = [w for w in ws if 'starter' in w.get('name','').lower()] or ws
print(preferred[0]['id'] if preferred else '')
")

if [[ -z "$WAREHOUSE_ID" ]]; then
    echo "[render-profile] no SQL warehouse found in workspace" >&2
    exit 1
fi

HOST_BARE="${DATABRICKS_HOST#https://}"
HOST_BARE="${HOST_BARE#http://}"

mkdir -p "$HOME/.dbt"
PROFILE_PATH="$HOME/.dbt/profiles.yml"

TEMP_NEW=$(mktemp)
cat > "$TEMP_NEW" <<EOF
northwind_payments:
  target: dev
  outputs:
    dev:
      type: databricks
      catalog: northwind_payments
      schema: silver
      host: $HOST_BARE
      http_path: /sql/1.0/warehouses/$WAREHOUSE_ID
      token: $DATABRICKS_TOKEN
      threads: 4
EOF

# Snowflake target — only added if SNOWFLAKE_ACCOUNT is set in .env
if [[ -n "${SNOWFLAKE_ACCOUNT:-}" && -n "${SNOWFLAKE_USER:-}" && -n "${SNOWFLAKE_PASSWORD:-}" ]]; then
    cat >> "$TEMP_NEW" <<EOF
    snowflake_dev:
      type: snowflake
      account: $SNOWFLAKE_ACCOUNT
      user: $SNOWFLAKE_USER
      password: $SNOWFLAKE_PASSWORD
      role: ${SNOWFLAKE_ROLE:-ACCOUNTADMIN}
      database: ${SNOWFLAKE_DATABASE:-NORTHWIND_PAYMENTS}
      warehouse: ${SNOWFLAKE_WAREHOUSE:-NORTHWIND_WH}
      schema: silver
      threads: 4
      client_session_keep_alive: false
EOF
    echo "[render-profile] also wrote snowflake_dev target"
fi

uv run python3 <<PY
import yaml, os
new = yaml.safe_load(open("$TEMP_NEW"))
existing = {}
if os.path.exists("$PROFILE_PATH"):
    try:
        existing = yaml.safe_load(open("$PROFILE_PATH")) or {}
    except yaml.YAMLError:
        existing = {}
existing.update(new)
with open("$PROFILE_PATH", "w") as f:
    yaml.safe_dump(existing, f, default_flow_style=False, sort_keys=False)
os.chmod("$PROFILE_PATH", 0o600)
print(f"[render-profile] wrote $PROFILE_PATH (warehouse $WAREHOUSE_ID, host $HOST_BARE)")
PY

rm -f "$TEMP_NEW"
