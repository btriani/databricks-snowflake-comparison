#!/usr/bin/env bash
set -euo pipefail

# NorthWind Payments — validate cost-tracking
#
# Runs the SQL from the M1 cost-tracking notebook against system.billing.usage
# and reports actual spend attributed to project=northwind-payments.

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

# Extract just the SQL block from the M1 notebook (skip MAGIC headers)
SQL=$(python3 <<'PY'
text = open("databricks/notebooks/cost_tracking.py").read()
in_sql = False
buf = []
for line in text.splitlines():
    s = line.strip()
    if s.startswith("# MAGIC %sql"):
        in_sql = True
        continue
    if in_sql and s.startswith("# MAGIC"):
        buf.append(s.replace("# MAGIC ", "").replace("# MAGIC", "").strip())
print(" ".join(buf))
PY
)

if [[ -z "$SQL" ]]; then
    echo "[validate-cost] ERROR: could not extract SQL from cost_tracking.py" >&2
    exit 1
fi

echo "[validate-cost] running cost query..."
BODY=$(SQL="$SQL" WAREHOUSE_ID="$WAREHOUSE_ID" python3 -c "
import json, os
print(json.dumps({
    'warehouse_id': os.environ['WAREHOUSE_ID'],
    'statement': os.environ['SQL'],
    'wait_timeout': '50s'
}))
")
RESPONSE=$(databricks api post /api/2.0/sql/statements --json "$BODY")

RESPONSE="$RESPONSE" python3 <<'PY'
import json, os, sys
r = json.loads(os.environ['RESPONSE'])
state = r.get('status', {}).get('state')
if state != 'SUCCEEDED':
    err = r.get('status', {}).get('error', {})
    print(f"[validate-cost] query state={state}, error={err}")
    sys.exit(1)

cols = [c['name'] for c in r.get('manifest', {}).get('schema', {}).get('columns', [])]
rows = r.get('result', {}).get('data_array', [])
print(f"[validate-cost] {len(rows)} row(s) returned")
if cols:
    print("  | " + " | ".join(cols) + " |")
    print("  |" + "|".join(["-" * (len(c)+2) for c in cols]) + "|")
for row in rows[:20]:
    print("  | " + " | ".join(str(v) for v in row) + " |")
if not rows:
    print("  (no rows yet — system.billing.usage typically lags 24-48 hours;")
    print("   re-run tomorrow if M2a/M2b spend hasn't shown up)")
PY

echo "[validate-cost] done"
