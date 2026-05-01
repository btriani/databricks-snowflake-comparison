.PHONY: help install generate generate-large test verify teardown setup-databricks ingest-databricks verify-databricks-bronze dbt-debug dbt-build dbt-test apply-security deploy-dashboard validate-cost setup-snowflake ingest-snowflake dbt-build-snowflake apply-security-snowflake deploy-streamlit-snowflake validate-cost-snowflake parity-check

help:
	@echo "NorthWind Payments Lakehouse — make targets"
	@echo ""
	@echo "  make install        Install Python deps via uv"
	@echo "  make generate       Generate 100K rows of dirty bronze data into ./data/landing/"
	@echo "  make generate-large Generate 10M rows (slower; for full pipeline runs)"
	@echo "  make test           Run unit tests"
	@echo "  make verify         M1: run unit tests. M2/M3 will add cross-platform parity checks."
	@echo "  make teardown       Remove local landing data + cloud resources (M2/M3 populate cloud)"
	@echo "  make setup-databricks       Pre-flight + UC catalog/schemas/Volume creation"
	@echo "  make ingest-databricks      Push landing/ to Volume + run Auto Loader"
	@echo "  make verify-databricks-bronze  Sanity SQL on bronze tables"
	@echo "  make dbt-debug              Render dbt profile + dbt debug (connection test)"
	@echo "  make dbt-build              dbt deps + dbt build (silver + gold + tests)"
	@echo "  make dbt-test               dbt test only (assumes models already built)"
	@echo "  make apply-security         Create security schema, masking functions, apply masks"
	@echo "  make deploy-dashboard       Deploy AI/BI Lakeview dashboard to workspace"
	@echo "  make validate-cost          Run the M1 cost-tracking notebook against real spend"

install:
	uv sync

generate:
	uv run npl-generate --rows 100000 --customers 5000 --merchants 500 --seed 42 --output ./data/landing/

generate-large:
	uv run npl-generate --rows 10000000 --customers 100000 --merchants 1000 --seed 42 --output ./data/landing/

test:
	uv run pytest -v

verify: test

teardown:
	bash scripts/teardown.sh

setup-databricks:
	bash scripts/databricks_preflight.sh
	bash scripts/setup_uc.sh

ingest-databricks:
	bash scripts/push_landing_to_volume.sh
	@DATABRICKS_TOKEN=$$(grep '^DATABRICKS_TOKEN=' .env 2>/dev/null | cut -d= -f2-); \
		DATABRICKS_HOST=$$(grep '^DATABRICKS_HOST=' .env 2>/dev/null | cut -d= -f2-); \
		WAREHOUSE_ID=$$(DATABRICKS_TOKEN="$$DATABRICKS_TOKEN" DATABRICKS_HOST="$$DATABRICKS_HOST" databricks warehouses list --output json | python3 -c "import json,sys; ws=json.load(sys.stdin); ws=ws if isinstance(ws,list) else ws.get('warehouses',[]); pref=[w for w in ws if 'starter' in w.get('name','').lower()] or ws; print(pref[0]['id'] if pref else '')"); \
		cd databricks/bundle && DATABRICKS_TOKEN="$$DATABRICKS_TOKEN" DATABRICKS_HOST="$$DATABRICKS_HOST" databricks bundle deploy --target dev --var="warehouse_id=$$WAREHOUSE_ID"
	@DATABRICKS_TOKEN=$$(grep '^DATABRICKS_TOKEN=' .env 2>/dev/null | cut -d= -f2-); \
		DATABRICKS_HOST=$$(grep '^DATABRICKS_HOST=' .env 2>/dev/null | cut -d= -f2-); \
		cd databricks/bundle && DATABRICKS_TOKEN="$$DATABRICKS_TOKEN" DATABRICKS_HOST="$$DATABRICKS_HOST" databricks bundle run bronze_ingest --target dev

verify-databricks-bronze:
	@echo "Run the queries in databricks/queries/verify_bronze.sql against the workspace SQL Editor."
	@echo "(Scripted variant: 'databricks api post /api/2.0/sql/statements --json {...}'.)"

dbt-debug:
	bash scripts/render_dbt_profile.sh
	cd dbt && uv run dbt deps
	cd dbt && uv run dbt debug

dbt-build:
	bash scripts/render_dbt_profile.sh
	cd dbt && uv run dbt deps
	cd dbt && uv run dbt build

dbt-test:
	cd dbt && uv run dbt test

apply-security:
	bash scripts/apply_security.sh

deploy-dashboard:
	bash scripts/deploy_dashboard.sh

validate-cost:
	bash scripts/validate_cost.sh

# ─── Snowflake (M3) ───

setup-snowflake:
	bash scripts/snowflake_preflight.sh
	snow sql -f snowflake/ddl/01_setup.sql

ingest-snowflake:
	bash scripts/push_landing_to_snowflake.sh
	snow sql -f snowflake/notebooks/02_bronze_copy.sql

dbt-build-snowflake:
	bash scripts/render_dbt_profile.sh
	cd dbt && uv run dbt deps
	cd dbt && uv run dbt build --target snowflake_dev

apply-security-snowflake:
	bash scripts/apply_security_snowflake.sh

deploy-streamlit-snowflake:
	bash scripts/deploy_streamlit_snowflake.sh

validate-cost-snowflake:
	bash scripts/validate_cost_snowflake.sh

parity-check:
	uv run python scripts/parity_check.py
