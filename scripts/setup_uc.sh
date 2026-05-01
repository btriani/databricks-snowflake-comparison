#!/usr/bin/env bash
set -euo pipefail

# NorthWind Payments — Unity Catalog setup
#
# Idempotent. Runs the SQL in databricks/notebooks/01_setup_uc.sql against the
# configured workspace using the Statement Execution API.

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi

: "${DATABRICKS_HOST:?run scripts/databricks_preflight.sh first}"
: "${DATABRICKS_TOKEN:?run scripts/databricks_preflight.sh first}"

echo "[setup-uc] resolving SQL warehouse..."
WAREHOUSE_ID=$(databricks warehouses list --output json | python3 -c "
import json, sys
hs = json.load(sys.stdin)
warehouses = hs if isinstance(hs, list) else hs.get('warehouses', [])
preferred = [w for w in warehouses if 'starter' in w.get('name', '').lower()]
chosen = preferred[0] if preferred else (warehouses[0] if warehouses else None)
print(chosen['id'] if chosen else 'NONE')
")

if [[ "$WAREHOUSE_ID" == "NONE" ]]; then
    echo "[setup-uc] No SQL warehouse found. Creating a transient XS serverless warehouse..."
    WAREHOUSE_ID=$(databricks warehouses create \
        --name "northwind-setup-xs" \
        --cluster-size "2X-Small" \
        --warehouse-type "PRO" \
        --enable-serverless-compute \
        --auto-stop-mins 5 \
        --output json | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
    echo "[setup-uc] Created warehouse $WAREHOUSE_ID"
fi

echo "[setup-uc] Using warehouse $WAREHOUSE_ID"

# Execute statements one at a time via the Statement Execution API.
python3 <<PY
import json, re, subprocess, sys

WAREHOUSE_ID = "$WAREHOUSE_ID"

text = open("databricks/notebooks/01_setup_uc.sql").read()
lines = []
for ln in text.splitlines():
    s = ln.strip()
    if s.startswith("-- MAGIC") or s == "-- COMMAND ----------" or s == "-- Databricks notebook source":
        continue
    lines.append(ln)
sql = "\n".join(lines)
sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)

statements = [s.strip() for s in sql.split(";") if s.strip()]
print(f"[setup-uc] Executing {len(statements)} statement(s)...", flush=True)

for i, stmt in enumerate(statements, 1):
    preview = stmt.replace("\n", " ")[:80]
    print(f"[setup-uc] [{i}/{len(statements)}] {preview}...", flush=True)
    body = json.dumps({
        "warehouse_id": WAREHOUSE_ID,
        "statement": stmt,
        "wait_timeout": "30s",
    })
    r = subprocess.run(
        ["databricks", "api", "post", "/api/2.0/sql/statements", "--json", body],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        print(f"[setup-uc] FAILED: {r.stderr}", file=sys.stderr)
        sys.exit(1)
    # Parse result; accept SUCCEEDED. PENDING means the wait_timeout expired
    # before completion — usually means a long warehouse cold-start. Poll.
    try:
        result = json.loads(r.stdout)
        state = result.get("status", {}).get("state", "UNKNOWN")
    except Exception:
        print(f"[setup-uc] Non-JSON response: {r.stdout[:200]}", file=sys.stderr)
        sys.exit(1)

    statement_id = result.get("statement_id")
    while state in ("PENDING", "RUNNING") and statement_id:
        import time
        time.sleep(2)
        poll = subprocess.run(
            ["databricks", "api", "get", f"/api/2.0/sql/statements/{statement_id}"],
            capture_output=True, text=True,
        )
        if poll.returncode != 0:
            print(f"[setup-uc] poll FAILED: {poll.stderr}", file=sys.stderr)
            sys.exit(1)
        result = json.loads(poll.stdout)
        state = result.get("status", {}).get("state", "UNKNOWN")

    if state != "SUCCEEDED":
        err = result.get("status", {}).get("error", {})
        print(f"[setup-uc] statement state={state}, error={err}", file=sys.stderr)
        sys.exit(1)

print("[setup-uc] All statements OK")
PY

echo "[setup-uc] done"
