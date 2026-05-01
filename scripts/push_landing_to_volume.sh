#!/usr/bin/env bash
set -euo pipefail

# NorthWind Payments — push local data/landing/ → UC Volume
#
# Pre-req: `make generate` has produced data/landing/*.parquet locally.
# Result: same files live at /Volumes/northwind_payments/bronze/landing/<run-id>/

if [[ -f ".env" ]]; then set -a; . .env; set +a; fi
: "${DATABRICKS_HOST:?see scripts/databricks_preflight.sh}"
: "${DATABRICKS_TOKEN:?see scripts/databricks_preflight.sh}"

LANDING_LOCAL="data/landing"
VOLUME_PATH="/Volumes/northwind_payments/bronze/landing"

if [[ ! -d "$LANDING_LOCAL" ]]; then
    echo "ERROR: $LANDING_LOCAL not found. Run 'make generate' first." >&2
    exit 1
fi

count=$(find "$LANDING_LOCAL" -maxdepth 1 -name "*.parquet" | wc -l | tr -d ' ')
if [[ "$count" -lt 6 ]]; then
    echo "ERROR: expected ≥6 parquet files in $LANDING_LOCAL, found $count. Re-run 'make generate'." >&2
    exit 1
fi

RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
TARGET="$VOLUME_PATH/$RUN_ID"

echo "[push] uploading $count parquet file(s) to $TARGET"

databricks fs mkdirs "dbfs:$TARGET" || true

for f in "$LANDING_LOCAL"/*.parquet; do
    base=$(basename "$f")
    echo "[push]   $base"
    databricks fs cp "$f" "dbfs:$TARGET/$base" --overwrite
done

# Also push FFIEC banks parquet to a separate reference/ folder (not run-id partitioned)
if [[ -f "data/landing/banks.parquet" ]]; then
    echo "[push]   banks.parquet (FFIEC reference)"
    databricks fs mkdirs "dbfs:$VOLUME_PATH/reference" || true
    databricks fs cp data/landing/banks.parquet "dbfs:$VOLUME_PATH/reference/banks.parquet" --overwrite
fi

echo "[push] uploaded to $TARGET"
echo "[push] listing remote:"
databricks fs ls "dbfs:$TARGET"
