#!/usr/bin/env bash
set -euo pipefail

# NorthWind Payments — deploy AI/BI Lakeview dashboard
#
# Idempotent. First run creates the dashboard; subsequent runs update it.
# Stores the dashboard ID in .dashboard_id (gitignored) for re-targeting.

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi
: "${DATABRICKS_HOST:?see scripts/databricks_preflight.sh}"
: "${DATABRICKS_TOKEN:?see scripts/databricks_preflight.sh}"

DASHBOARD_NAME="northwind-fraud-overview"
DASHBOARD_JSON="databricks/dashboards/fraud_overview.lvdash.json"
ID_FILE=".dashboard_id"

if [[ ! -f "$DASHBOARD_JSON" ]]; then
    echo "[deploy-dashboard] missing $DASHBOARD_JSON" >&2
    exit 1
fi

echo "[deploy-dashboard] CLI surface check (databricks lakeview --help):"
databricks lakeview --help 2>&1 | head -10 || echo "(lakeview subcommand not in this CLI version — using REST API directly)"

WAREHOUSE_ID=$(databricks warehouses list --output json | python3 -c "
import json, sys
hs = json.load(sys.stdin)
ws = hs if isinstance(hs, list) else hs.get('warehouses', [])
preferred = [w for w in ws if 'starter' in w.get('name','').lower()] or ws
print(preferred[0]['id'] if preferred else '')
")
echo "[deploy-dashboard] using warehouse $WAREHOUSE_ID"

# Read dashboard JSON as JSON-encoded string for embedding in API request
SERIALIZED=$(python3 -c "
import json
d = json.load(open('$DASHBOARD_JSON'))
print(json.dumps(json.dumps(d)))
")

if [[ -f "$ID_FILE" ]]; then
    DASHBOARD_ID=$(cat "$ID_FILE")
    echo "[deploy-dashboard] updating existing dashboard $DASHBOARD_ID"
    BODY=$(SERIALIZED="$SERIALIZED" WAREHOUSE_ID="$WAREHOUSE_ID" python3 -c "
import json, os
print(json.dumps({
    'display_name': '$DASHBOARD_NAME',
    'warehouse_id': os.environ['WAREHOUSE_ID'],
    'serialized_dashboard': json.loads(os.environ['SERIALIZED'])
}))
")
    databricks api patch "/api/2.0/lakeview/dashboards/$DASHBOARD_ID" --json "$BODY" | head -20
else
    echo "[deploy-dashboard] creating new dashboard"
    BODY=$(SERIALIZED="$SERIALIZED" WAREHOUSE_ID="$WAREHOUSE_ID" python3 -c "
import json, os
print(json.dumps({
    'display_name': '$DASHBOARD_NAME',
    'warehouse_id': os.environ['WAREHOUSE_ID'],
    'serialized_dashboard': json.loads(os.environ['SERIALIZED'])
}))
")
    RESPONSE=$(databricks api post "/api/2.0/lakeview/dashboards" --json "$BODY")
    NEW_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; r=json.load(sys.stdin); print(r.get('dashboard_id', ''))")
    if [[ -z "$NEW_ID" ]]; then
        echo "[deploy-dashboard] FAILED to extract dashboard_id from response:" >&2
        echo "$RESPONSE" | head -20 >&2
        exit 1
    fi
    echo "$NEW_ID" > "$ID_FILE"
    echo "[deploy-dashboard] created dashboard $NEW_ID; ID saved to $ID_FILE"
fi

DASH_ID=$(cat "$ID_FILE")

# Publish the dashboard so it is accessible at the /published URL.
# Without this step the dashboard is only a draft and renders blank in the browser.
echo "[deploy-dashboard] publishing dashboard $DASH_ID ..."
PUB_BODY=$(WAREHOUSE_ID="$WAREHOUSE_ID" DASHBOARD_NAME="$DASHBOARD_NAME" python3 -c "
import json, os
print(json.dumps({
    'display_name': os.environ['DASHBOARD_NAME'],
    'warehouse_id': os.environ['WAREHOUSE_ID'],
    'embed_credentials': True
}))
")
PUB_RESULT=$(databricks api post "/api/2.0/lakeview/dashboards/$DASH_ID/published" --json "$PUB_BODY")
PUB_STATE=$(echo "$PUB_RESULT" | python3 -c "import json,sys; r=json.load(sys.stdin); print(r.get('lifecycle_state', r.get('state','unknown')))" 2>/dev/null || echo "check above")
echo "[deploy-dashboard] publish result: $PUB_STATE"

echo "[deploy-dashboard] view at: $DATABRICKS_HOST/dashboardsv3/$DASH_ID/published"
echo "[deploy-dashboard] done"
