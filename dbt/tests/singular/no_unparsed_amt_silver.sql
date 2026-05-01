-- silver.transactions.amt should never be NULL or non-positive
SELECT trans_num, amt
FROM {{ ref('silver_transactions') }}
WHERE amt IS NULL OR amt <= 0
