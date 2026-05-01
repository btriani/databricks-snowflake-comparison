#!/usr/bin/env bash
set -euo pipefail

# NorthWind Payments — Security setup
#
# Creates the security schema + masking functions, creates groups (best effort),
# then applies masks to silver.customers and cleans up the silver_silver legacy schema.
# Idempotent. Safe to re-run.

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
    echo "[apply-security] no SQL warehouse found" >&2
    exit 1
fi

echo "[apply-security] using warehouse $WAREHOUSE_ID"

run_sql_file() {
    local sql_file="$1"
    if [[ ! -f "$sql_file" ]]; then
        echo "[apply-security] skip (not yet created): $sql_file"
        return 0
    fi
    echo "[apply-security] running $sql_file"
    WAREHOUSE_ID="$WAREHOUSE_ID" SQL_FILE="$sql_file" python3 <<'PY'
import json, os, re, subprocess, sys, time
WAREHOUSE_ID = os.environ['WAREHOUSE_ID']
SQL_FILE = os.environ['SQL_FILE']
text = open(SQL_FILE).read()
lines = []
for ln in text.splitlines():
    s = ln.strip()
    if s.startswith("-- MAGIC") or s == "-- COMMAND ----------" or s == "-- Databricks notebook source":
        continue
    lines.append(ln)
sql = "\n".join(lines)
sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)
statements = [s.strip() for s in sql.split(";") if s.strip()]
print(f"  {len(statements)} statement(s)", flush=True)
for i, stmt in enumerate(statements, 1):
    body = json.dumps({"warehouse_id": WAREHOUSE_ID, "statement": stmt, "wait_timeout": "30s"})
    r = subprocess.run(["databricks", "api", "post", "/api/2.0/sql/statements", "--json", body],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  FAILED on stmt {i}: {r.stderr}", file=sys.stderr); sys.exit(1)
    result = json.loads(r.stdout)
    state = result.get("status", {}).get("state", "UNKNOWN")
    statement_id = result.get("statement_id")
    while state in ("PENDING", "RUNNING") and statement_id:
        time.sleep(2)
        poll = subprocess.run(["databricks", "api", "get", f"/api/2.0/sql/statements/{statement_id}"],
                              capture_output=True, text=True)
        if poll.returncode != 0:
            print(f"  poll FAILED: {poll.stderr}", file=sys.stderr); sys.exit(1)
        result = json.loads(poll.stdout)
        state = result.get("status", {}).get("state", "UNKNOWN")
    if state != "SUCCEEDED":
        err = result.get("status", {}).get("error", {})
        print(f"  stmt {i} ended in state={state}, error={err}", file=sys.stderr); sys.exit(1)
print("  OK")
PY
}

# 1. Create security schema + masking functions
run_sql_file "databricks/notebooks/04_setup_security.sql"

# 2. Create UC account groups (best effort — fails silently if no permission)
echo "[apply-security] creating account groups (best effort)"
for g in npl_admin npl_pii_reader npl_analyst; do
    databricks account groups create --display-name "$g" 2>/dev/null && echo "  created $g" || echo "  skipped $g (already exists or no permission)"
done

# 3. Apply masks
run_sql_file "databricks/notebooks/05_apply_pii_masks.sql"

# 4. Cleanup legacy schema
run_sql_file "databricks/notebooks/06_cleanup_legacy.sql"

echo "[apply-security] done"
