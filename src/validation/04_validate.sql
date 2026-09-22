-- =============================================================================
-- Automated data quality gate
-- =============================================================================
-- Purpose:
--   Runs as the last task in the job, after Gold is built. Fails the job
--   (via raise_error) if referential integrity or surrogate-key uniqueness
--   is broken, so a bad load is caught by CI/CD rather than discovered
--   later in a BI tool. This is the CI/CD equivalent of the manual
--   validation query we ran by hand against the MySQL version.
-- =============================================================================

-- -----------------------------------------------------------------------
-- Check 1: referential integrity on fact_sales
-- -----------------------------------------------------------------------
SELECT
    CASE
        WHEN orphan_product_fk > 0 OR orphan_customer_fk > 0 THEN
            raise_error(
                concat(
                    'Referential integrity check FAILED: ',
                    orphan_product_fk, ' orphan product keys, ',
                    orphan_customer_fk, ' orphan customer keys out of ',
                    total_fact_rows, ' fact rows.'
                )
            )
        ELSE
            concat('PASSED: ', total_fact_rows, ' fact rows, 0 orphan foreign keys.')
    END AS referential_integrity_result
FROM (
    SELECT
        COUNT(*) AS total_fact_rows,
        SUM(CASE WHEN product_key  IS NULL THEN 1 ELSE 0 END) AS orphan_product_fk,
        SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END) AS orphan_customer_fk
    FROM bikemart.gold.fact_sales
) checks;

-- -----------------------------------------------------------------------
-- Check 2: surrogate key uniqueness on every dimension
-- -----------------------------------------------------------------------
SELECT
    CASE
        WHEN dup_countries > 0 OR dup_categories > 0 OR dup_customers > 0 OR dup_products > 0 THEN
            raise_error(
                concat(
                    'Surrogate key uniqueness check FAILED: ',
                    'dim_countries dupes=', dup_countries, ', ',
                    'dim_categories dupes=', dup_categories, ', ',
                    'dim_customers dupes=', dup_customers, ', ',
                    'dim_products dupes=', dup_products
                )
            )
        ELSE 'PASSED: every dimension surrogate key is unique.'
    END AS key_uniqueness_result
FROM (
    SELECT
        (SELECT COUNT(*) - COUNT(DISTINCT country_key)  FROM bikemart.gold.dim_countries)  AS dup_countries,
        (SELECT COUNT(*) - COUNT(DISTINCT category_key) FROM bikemart.gold.dim_categories) AS dup_categories,
        (SELECT COUNT(*) - COUNT(DISTINCT customer_key) FROM bikemart.gold.dim_customers)  AS dup_customers,
        (SELECT COUNT(*) - COUNT(DISTINCT product_key)  FROM bikemart.gold.dim_products)   AS dup_products
) key_checks;
