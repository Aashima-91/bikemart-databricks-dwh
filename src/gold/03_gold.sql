-- =============================================================================
-- Gold layer: business-ready snowflake schema
-- =============================================================================
-- Purpose:
--   Builds the same snowflake model as the MySQL version: dim_countries and
--   dim_categories as outriggers, dim_customers and dim_products as the core
--   dimensions, fact_sales at the center. Surrogate keys via ROW_NUMBER(),
--   never source natural keys. Validated locally against the real dataset:
--   identical row counts, zero orphan FKs, and identical revenue figures to
--   the tested MySQL version.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS bikemart.gold;

-- -----------------------------------------------------------------------
-- dim_countries: country_key = 0 reserved for "Unknown" (a customer with no
-- location row at all -- distinct from 'n/a', which is a legitimate value
-- already produced by Silver-layer cleaning for blank source data)
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.gold.dim_countries AS
SELECT 0 AS country_key, 'Unknown' AS country_name
UNION ALL
SELECT
    ROW_NUMBER() OVER (ORDER BY CNTRY) AS country_key,
    CNTRY AS country_name
FROM (SELECT DISTINCT CNTRY FROM bikemart.silver.erp_loc_a101);

-- -----------------------------------------------------------------------
-- dim_categories: category_key = 0 reserved for "Unknown" (a genuine ERP
-- source gap -- e.g. the 7 CO-PE pedal products with no category match)
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.gold.dim_categories AS
SELECT 0 AS category_key, 'n/a' AS category_id, 'Unknown' AS category,
       'Unknown' AS subcategory, 'n/a' AS maintenance
UNION ALL
SELECT
    ROW_NUMBER() OVER (ORDER BY ID) AS category_key,
    ID AS category_id, CAT AS category, SUBCAT AS subcategory, MAINTENANCE AS maintenance
FROM bikemart.silver.erp_px_cat_g1v2;

-- -----------------------------------------------------------------------
-- dim_customers: CRM is the master source for gender/marital status, ERP
-- is the gender fallback and sole source for birth_date, country resolved
-- via dim_countries with a COALESCE fallback to "Unknown"
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,
    ci.cst_id                              AS customer_id,
    ci.cst_key                             AS customer_number,
    ci.cst_firstname                       AS first_name,
    ci.cst_lastname                        AS last_name,
    COALESCE(ci.cst_marital_status, 'n/a') AS marital_status,
    CASE
        WHEN ci.cst_gndr IS NOT NULL AND ci.cst_gndr <> 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(eca.GEN, 'n/a')
    END                                     AS gender,
    eca.BDATE                              AS birth_date,
    COALESCE(dc.country_key, 0)            AS country_key,
    ci.cst_create_date                     AS create_date
FROM bikemart.silver.crm_cust_info ci
LEFT JOIN bikemart.silver.erp_cust_az12 eca ON ci.cst_key = eca.CID
LEFT JOIN bikemart.silver.erp_loc_a101 el   ON ci.cst_key = el.CID
LEFT JOIN bikemart.gold.dim_countries dc    ON el.CNTRY = dc.country_name;

-- -----------------------------------------------------------------------
-- dim_products: active/current products only (prd_end_dt IS NULL, avoids
-- SCD duplicates); product_number and category_key parsed from prd_key
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY p.prd_key) AS product_key,
    p.prd_id                               AS product_id,
    SUBSTRING(p.prd_key, 7)                AS product_number,
    p.prd_nm                               AS product_name,
    COALESCE(dcat.category_key, 0)         AS category_key,
    p.prd_cost                             AS cost,
    p.prd_line                             AS product_line,
    p.prd_start_dt                         AS start_date
FROM bikemart.silver.crm_prd_info p
LEFT JOIN bikemart.gold.dim_categories dcat
    ON REPLACE(SUBSTRING(p.prd_key, 1, 5), '-', '_') = dcat.category_id
WHERE p.prd_end_dt IS NULL;

-- -----------------------------------------------------------------------
-- fact_sales: sls_order_dt/ship_dt/due_dt are still INT (YYYYMMDD) in
-- Silver; cast to true DATE here now that Gold defines its own schema.
-- No fallback on product_key/customer_key by design -- a genuine join
-- failure here should surface as NULL, not be masked (see 04_validate.sql)
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.gold.fact_sales AS
SELECT
    sd.sls_ord_num AS order_number,
    dp.product_key,
    dc.customer_key,
    CASE
        WHEN sd.sls_order_dt IS NULL THEN NULL
        ELSE to_date(CAST(sd.sls_order_dt AS STRING), 'yyyyMMdd')
    END AS order_date,
    to_date(CAST(sd.sls_ship_dt AS STRING), 'yyyyMMdd') AS shipping_date,
    to_date(CAST(sd.sls_due_dt AS STRING), 'yyyyMMdd')  AS due_date,
    sd.sls_sales    AS sales_amount,
    sd.sls_quantity AS quantity,
    sd.sls_price    AS price
FROM bikemart.silver.crm_sales_details sd
LEFT JOIN bikemart.gold.dim_products dp  ON sd.sls_prd_key = dp.product_number
LEFT JOIN bikemart.gold.dim_customers dc ON sd.sls_cust_id = dc.customer_id;
