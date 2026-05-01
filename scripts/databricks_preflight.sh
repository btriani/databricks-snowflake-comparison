#!/usr/bin/env bash
set -euo pipefail

# NorthWind Payments — Databricks pre-flight
#
# Verifies the local environment can talk to the configured Databricks workspace.
# Idempotent. Safe to re-run.

# Load .env if present
if [[ -f ".env" ]]; then
    set -a
    # shellcheck disable=SC1091
    . .env
    set +a
fi

: "${DATABRICKS_HOST:?DATABRICKS_HOST not set — copy .env.example to .env and fill in values}"
: "${DATABRICKS_TOKEN:?DATABRICKS_TOKEN not set — see .env.example}"

echo "[preflight] Databricks CLI version:"
databricks --version

echo "[preflight] Workspace: $DATABRICKS_HOST"

echo "[preflight] Validating credentials (databricks current-user me):"
databricks current-user me --output json | head -20

echo "[preflight] Listing accessible catalogs (Unity Catalog reachability check):"
databricks catalogs list --output json | python3 -c "
import json, sys
data = json.load(sys.stdin)
catalogs = []
if isinstance(data, list):
    catalogs = [c.get('name') for c in data if c.get('name')]
elif isinstance(data, dict):
    catalogs = [c.get('name') for c in data.get('catalogs', []) if c.get('name')]
print(f'  Found {len(catalogs)} catalog(s): {catalogs[:5]}{\" ...\" if len(catalogs) > 5 else \"\"}')
if not catalogs:
    print('  WARNING: no catalogs visible — Unity Catalog may not be enabled or you lack USE_CATALOG grants.')
    sys.exit(2)
"

echo "[preflight] OK"
