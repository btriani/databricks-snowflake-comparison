-- silver.transactions should NEVER reference a customer_sk that doesn't exist
-- in silver.customers (the inner join in silver_transactions enforces this,
-- but the test catches regressions).
SELECT t.trans_num, t.customer_sk
FROM {{ ref('silver_transactions') }} t
LEFT JOIN {{ ref('silver_customers') }} c ON c.customer_sk = t.customer_sk
WHERE c.customer_sk IS NULL
