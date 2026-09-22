-- =============================================================================
-- Silver layer: cleaning and standardization
-- =============================================================================
-- Purpose:
--   Reads from Bronze, applies the same cleaning rules as the MySQL version
--   (load_silver.sql), writes to Delta tables in the silver schema.
--   This logic was validated locally against the real dataset using PySpark
--   before being ported here -- row counts, dedup behavior, and cleaned
--   values matched the tested MySQL output exactly.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS bikemart.silver;

-- -----------------------------------------------------------------------
-- crm_cust_info: trim names, normalize marital status/gender, de-duplicate
-- on cst_id keeping the most recent by cst_create_date, drop blank/zero IDs
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.silver.crm_cust_info AS
SELECT
    CAST(cst_id AS INT)           AS cst_id,
    TRIM(cst_key)                  AS cst_key,
    TRIM(cst_firstname)            AS cst_firstname,
    TRIM(cst_lastname)             AS cst_lastname,
    CASE UPPER(TRIM(cst_marital_status))
        WHEN 'M' THEN 'Married'
        WHEN 'S' THEN 'Single'
        ELSE 'n/a'
    END AS cst_marital_status,
    CASE UPPER(TRIM(cst_gndr))
        WHEN 'M' THEN 'Male'
        WHEN 'F' THEN 'Female'
        ELSE 'n/a'
    END AS cst_gndr,
    CAST(cst_create_date AS DATE)  AS cst_create_date
FROM (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(cst_id AS INT)
            ORDER BY CAST(cst_create_date AS DATE) DESC
        ) AS flag_latest
    FROM bikemart.bronze.crm_cust_info b
    WHERE cst_id IS NOT NULL AND TRIM(cst_id) <> '' AND CAST(cst_id AS INT) <> 0
) t
WHERE flag_latest = 1;

-- -----------------------------------------------------------------------
-- crm_prd_info: fill missing cost with 0, expand product line codes,
-- recalculate prd_end_dt as one day before the next version's start date
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.silver.crm_prd_info AS
SELECT
    CAST(prd_id AS INT)                    AS prd_id,
    prd_key,
    prd_nm,
    COALESCE(CAST(prd_cost AS INT), 0)     AS prd_cost,
    CASE UPPER(TRIM(prd_line))
        WHEN 'R' THEN 'Road'
        WHEN 'M' THEN 'Mountain'
        WHEN 'S' THEN 'Other'
        WHEN 'T' THEN 'Touring'
        ELSE 'n/a'
    END AS prd_line,
    CAST(prd_start_dt AS DATE)             AS prd_start_dt,
    DATE_SUB(
        LEAD(CAST(prd_start_dt AS DATE)) OVER (
            PARTITION BY prd_key ORDER BY CAST(prd_start_dt AS DATE)
        ),
        1
    ) AS prd_end_dt
FROM bikemart.bronze.crm_prd_info;

-- -----------------------------------------------------------------------
-- crm_sales_details: null out invalid order dates; derive price from
-- sales/quantity when missing or non-positive; recalculate sales from the
-- SAME cleaned price (not the raw one -- see load_silver.sql history for
-- why that distinction matters) when missing, non-positive, or mismatched
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.silver.crm_sales_details AS
SELECT
    sls_ord_num,
    sls_prd_key,
    CAST(sls_cust_id AS INT) AS sls_cust_id,
    CASE
        WHEN sls_order_dt = '0' OR LENGTH(TRIM(sls_order_dt)) <> 8 THEN NULL
        ELSE CAST(sls_order_dt AS INT)
    END AS sls_order_dt,
    CAST(sls_ship_dt AS INT) AS sls_ship_dt,
    CAST(sls_due_dt AS INT)  AS sls_due_dt,
    CASE
        WHEN sls_sales_int IS NULL OR sls_sales_int <= 0
             OR sls_sales_int <> sls_quantity_int * cleaned_price
            THEN sls_quantity_int * cleaned_price
        ELSE sls_sales_int
    END AS sls_sales,
    sls_quantity_int AS sls_quantity,
    cleaned_price     AS sls_price
FROM (
    SELECT
        sls_ord_num, sls_prd_key, sls_cust_id,
        sls_order_dt, sls_ship_dt, sls_due_dt,
        CAST(sls_sales AS INT)    AS sls_sales_int,
        CAST(sls_quantity AS INT) AS sls_quantity_int,
        CASE
            WHEN CAST(sls_price AS INT) IS NULL OR CAST(sls_price AS INT) <= 0
                THEN CAST(sls_sales AS INT) / NULLIF(CAST(sls_quantity AS INT), 0)
            ELSE CAST(sls_price AS INT)
        END AS cleaned_price
    FROM bikemart.bronze.crm_sales_details
) priced;

-- -----------------------------------------------------------------------
-- erp_cust_az12: strip "NAS" prefix, null out future birth dates,
-- normalize gender
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.silver.erp_cust_az12 AS
SELECT
    CASE WHEN CID LIKE 'NAS%' THEN SUBSTRING(CID, 4) ELSE CID END AS CID,
    CASE
        WHEN CAST(BDATE AS DATE) > CURRENT_DATE() THEN NULL
        ELSE CAST(BDATE AS DATE)
    END AS BDATE,
    CASE UPPER(TRIM(GEN))
        WHEN 'M' THEN 'Male'
        WHEN 'MALE' THEN 'Male'
        WHEN 'F' THEN 'Female'
        WHEN 'FEMALE' THEN 'Female'
        ELSE 'n/a'
    END AS GEN
FROM bikemart.bronze.erp_cust_az12;

-- -----------------------------------------------------------------------
-- erp_loc_a101: strip hyphens from CID, normalize country names
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.silver.erp_loc_a101 AS
SELECT
    REPLACE(CID, '-', '') AS CID,
    CASE
        WHEN TRIM(CNTRY) IN ('US', 'USA') THEN 'United States'
        WHEN TRIM(CNTRY) = 'DE' THEN 'Germany'
        WHEN TRIM(CNTRY) = '' OR CNTRY IS NULL THEN 'n/a'
        ELSE TRIM(CNTRY)
    END AS CNTRY
FROM bikemart.bronze.erp_loc_a101;

-- -----------------------------------------------------------------------
-- erp_px_cat_g1v2: no data quality issues found in the EDA; trimmed only
-- -----------------------------------------------------------------------
CREATE OR REPLACE TABLE bikemart.silver.erp_px_cat_g1v2 AS
SELECT
    TRIM(ID)          AS ID,
    TRIM(CAT)         AS CAT,
    TRIM(SUBCAT)      AS SUBCAT,
    TRIM(MAINTENANCE) AS MAINTENANCE
FROM bikemart.bronze.erp_px_cat_g1v2;
