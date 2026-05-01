# Databricks notebook source
# MAGIC %md
# MAGIC # NorthWind Payments — Cost Tracking
# MAGIC
# MAGIC Queries `system.billing.usage` to report Databricks DBU spend per workspace,
# MAGIC scoped to the NorthWind tagging convention. Run after each end-to-end pipeline
# MAGIC execution to verify the per-run budget (≤ $1.50 compute, ≤ $0.75 SQL warehouse).
# MAGIC
# MAGIC **Pre-req (M2):** Unity Catalog enabled, `system.billing` schema readable.

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   usage_date,
# MAGIC   sku_name,
# MAGIC   ROUND(SUM(usage_quantity), 4) AS dbus,
# MAGIC   ROUND(SUM(usage_quantity) * 0.55, 2) AS approx_usd
# MAGIC FROM system.billing.usage
# MAGIC WHERE usage_date >= current_date() - INTERVAL 7 DAYS
# MAGIC   AND custom_tags['project'] = 'northwind-payments'
# MAGIC GROUP BY usage_date, sku_name
# MAGIC ORDER BY usage_date DESC, dbus DESC
