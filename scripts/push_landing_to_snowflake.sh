#!/usr/bin/env bash
set -euo pipefail

# Push generated landing parquet files to Snowflake internal stage.
# Idempotent — PUT with OVERWRITE=TRUE re-uploads files of the same name.

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi
: "${SNOWFLAKE_DATABASE:=NORTHWIND_PAYMENTS}"

LANDING_DIR="${LANDING_DIR:-./data/landing}"

if [[ ! -d "$LANDING_DIR" ]]; then
    echo "[push-snowflake] no $LANDING_DIR — run 'make generate' first" >&2
    exit 1
fi

N_FILES=$(find "$LANDING_DIR" -maxdepth 1 -name '*.parquet' | wc -l | tr -d ' ')
echo "[push-snowflake] uploading $N_FILES parquet files to @${SNOWFLAKE_DATABASE}.BRONZE.NORTHWIND_LANDING"

for f in "$LANDING_DIR"/*.parquet; do
    fname=$(basename "$f")
    echo "[push-snowflake]   → $fname"
    snow sql -q "PUT 'file://$(pwd)/$f' @${SNOWFLAKE_DATABASE}.BRONZE.NORTHWIND_LANDING/ OVERWRITE=TRUE AUTO_COMPRESS=FALSE" --format json > /tmp/snowflake_put.json
done

echo "[push-snowflake] verifying..."
snow sql -q "LIST @${SNOWFLAKE_DATABASE}.BRONZE.NORTHWIND_LANDING" --format json | python3 -c "
import json, sys
rows = json.load(sys.stdin)
print(f'[push-snowflake] {len(rows)} files on stage:')
for r in rows[:20]:
    print(f\"  - {r.get('name')} ({r.get('size','?')} bytes)\")
"

echo "[push-snowflake] done."
