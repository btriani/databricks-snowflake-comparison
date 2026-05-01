-- M2c PII mask verification. Run after `make apply-security`.

-- 1. List all column masks attached to silver tables
SELECT
    table_catalog || '.' || table_schema || '.' || table_name AS table_full_name,
    column_name
FROM system.information_schema.column_masks
WHERE table_catalog = 'northwind_payments'
  AND table_schema = 'silver'
ORDER BY table_full_name, column_name;

-- 2. Verify the masking functions exist
SELECT routine_schema || '.' || routine_name AS function_full_name, data_type
FROM system.information_schema.routines
WHERE routine_catalog = 'northwind_payments'
  AND routine_schema = 'security'
ORDER BY routine_name;

-- 3. Sample the customer data — admins bypass masks (returns RAW)
SELECT cc_num, first AS first_name, last AS last_name, street, dob
FROM northwind_payments.silver.customers_snapshot
LIMIT 5;

-- 4. Direct function call — admins bypass (returns RAW); analysts would see masked
SELECT
    northwind_payments.security.mask_cc_num('1234567890123456') AS sample_cc,
    northwind_payments.security.mask_name('Alice')              AS sample_name,
    northwind_payments.security.mask_dob(DATE'1985-04-12')      AS sample_dob;
