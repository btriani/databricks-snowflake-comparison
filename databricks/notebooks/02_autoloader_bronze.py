# Databricks notebook source
# MAGIC %md
# MAGIC # Auto Loader → bronze (M2a)
# MAGIC
# MAGIC Reads parquet files dropped into the landing Volume by `npl-generate` and
# MAGIC writes them to bronze Delta tables. Handles the v1/v2 schema split as one
# MAGIC unified table via `cloudFiles.schemaEvolutionMode = 'addNewColumns'`.
# MAGIC
# MAGIC Bronze schema-on-read: every column lands as raw type from parquet. The
# MAGIC silver layer (M2b) is responsible for typing/cleansing.
# MAGIC
# MAGIC **Important:** per the M1 implementation findings, `amt` (and the v2
# MAGIC equivalent `transaction_amount`) arrive as STRING in parquet — pyarrow
# MAGIC forced this when M1's CLI cast mixed-type columns. Auto Loader will land
# MAGIC them as STRING in bronze; silver parses to DECIMAL.

# COMMAND ----------

dbutils.widgets.text("catalog", "northwind_payments")
dbutils.widgets.text("bronze_schema", "bronze")
dbutils.widgets.text("landing", "/Volumes/northwind_payments/bronze/landing")
dbutils.widgets.text("checkpoints", "/Volumes/northwind_payments/bronze/_checkpoints")

CATALOG = dbutils.widgets.get("catalog")
SCHEMA = dbutils.widgets.get("bronze_schema")
LANDING = dbutils.widgets.get("landing")
CHECKPOINTS = dbutils.widgets.get("checkpoints")

# COMMAND ----------

# Make sure the checkpoint Volume exists
spark.sql(f"CREATE VOLUME IF NOT EXISTS {CATALOG}.{SCHEMA}._checkpoints")

# COMMAND ----------

def ingest(table: str, file_glob: str, schema_hints: str | None = None) -> int:
    """Run a one-shot Auto Loader stream that ingests `file_glob` into `table`.

    Returns the row count after ingest. Idempotent thanks to the checkpoint
    location (re-running on the same files is a no-op).
    """
    target = f"{CATALOG}.{SCHEMA}.{table}"
    checkpoint = f"{CHECKPOINTS}/{table}"
    schema_loc = f"{CHECKPOINTS}/{table}_schema"

    reader = (
        spark.readStream
            .format("cloudFiles")
            .option("cloudFiles.format", "parquet")
            .option("cloudFiles.schemaLocation", schema_loc)
            .option("cloudFiles.schemaEvolutionMode", "addNewColumns")
            .option("cloudFiles.includeExistingFiles", "true")
            .option("pathGlobFilter", file_glob)
    )
    if schema_hints:
        reader = reader.option("cloudFiles.schemaHints", schema_hints)

    df = (reader.load(LANDING)
        .selectExpr(
            "*",
            "current_timestamp() AS _ingest_timestamp",
            "_metadata.file_path AS _source_file",
        )
    )

    (df.writeStream
        .format("delta")
        .option("checkpointLocation", checkpoint)
        .option("mergeSchema", "true")
        .trigger(availableNow=True)
        .toTable(target)
    )

    return spark.table(target).count()

# COMMAND ----------

# Transactions: union v1 and v2 via schema evolution
n_txns = ingest(
    table="transactions",
    file_glob="transactions_v*.parquet",
    schema_hints="cc_num STRING, amt STRING, transaction_amount STRING, trans_num STRING",
)
print(f"bronze.transactions: {n_txns:,} rows")

# COMMAND ----------

n_cust = ingest(
    table="customers",
    file_glob="customers.parquet",
    schema_hints="cc_num STRING",
)
print(f"bronze.customers: {n_cust:,} rows")

# COMMAND ----------

n_merch = ingest(
    table="merchants",
    file_glob="merchants.parquet",
)
print(f"bronze.merchants: {n_merch:,} rows")

# COMMAND ----------

# Tag the tables with project metadata (for cost-tracking attribution)
for t in ("transactions", "customers", "merchants"):
    spark.sql(f"ALTER TABLE {CATALOG}.{SCHEMA}.{t} SET TAGS ('project' = 'northwind-payments', 'milestone' = 'm2a')")

# COMMAND ----------

# Final summary
display(spark.sql(f"""
    SELECT 'transactions' AS table_name, COUNT(*) AS row_count FROM {CATALOG}.{SCHEMA}.transactions
    UNION ALL SELECT 'customers',  COUNT(*) FROM {CATALOG}.{SCHEMA}.customers
    UNION ALL SELECT 'merchants',  COUNT(*) FROM {CATALOG}.{SCHEMA}.merchants
    ORDER BY table_name
"""))
