-- NorthWind Payments — Cost Tracking (Snowflake)
--
-- Queries SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY to report credit spend
-- per warehouse over the last 7 days, scoped to NorthWind warehouses by name.
-- Run after each end-to-end run. M3 wires this into `make verify` for the Snowflake side.
--
-- Pre-req (M3): The role running this query must have IMPORTED PRIVILEGES on the
-- SNOWFLAKE database. Per-credit USD rate depends on edition (default below assumes
-- Standard at $2.00/credit; adjust for your contract).

USE ROLE ACCOUNTADMIN;

SELECT
    DATE_TRUNC('day', start_time) AS usage_day,
    warehouse_name,
    ROUND(SUM(credits_used), 4) AS credits,
    ROUND(SUM(credits_used) * 2.00, 2) AS approx_usd
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND warehouse_name ILIKE 'NORTHWIND%'
GROUP BY usage_day, warehouse_name
ORDER BY usage_day DESC, credits DESC;
