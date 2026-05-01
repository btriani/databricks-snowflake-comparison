-- gold.fct_merchant_exposure totals must be non-negative
SELECT merchant_name, total_amt, fraud_amt
FROM {{ ref('gold_fct_merchant_exposure') }}
WHERE total_amt < 0 OR fraud_amt < 0
