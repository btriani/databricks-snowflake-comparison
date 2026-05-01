-- gold.kpi_executive must have exactly one row per distinct trans_date
SELECT trans_date, COUNT(*) AS n
FROM {{ ref('gold_kpi_executive') }}
GROUP BY trans_date
HAVING COUNT(*) > 1
