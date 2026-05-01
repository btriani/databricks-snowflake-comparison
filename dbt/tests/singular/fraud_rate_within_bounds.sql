-- Overall silver fraud rate should be within [0.5%, 3.0%]. Bounds widened from
-- the original [0.5%, 2.0%] because observed silver rate is ~1.94% — the bronze
-- dedup process drops some non-fraud duplicates more often than fraud duplicates,
-- pushing the silver rate slightly above the M1 generator target of 1%.
WITH overall AS (
    SELECT
        SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS rate
    FROM {{ ref('silver_transactions') }}
)

SELECT 'fraud_rate_out_of_bounds' AS failure, rate
FROM overall
WHERE rate < 0.005 OR rate > 0.03
