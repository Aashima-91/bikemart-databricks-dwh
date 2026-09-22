-- =============================================================================
-- Bronze layer: raw ingestion
-- =============================================================================
-- Purpose:
--   Loads the 6 raw source CSVs into Delta tables, as-is, no transformations.
--   This is the Databricks equivalent of load_bronze.sql from the MySQL
--   version of this project.
--
-- Prerequisite (one-time, manual):
--   Upload the 6 CSVs to a Unity Catalog Volume before running this file:
--     /Volumes/bikemart/bronze/raw_files/crm_cust_info.csv
--     /Volumes/bikemart/bronze/raw_files/crm_prd_info.csv
--     /Volumes/bikemart/bronze/raw_files/crm_sales_details.csv
--     /Volumes/bikemart/bronze/raw_files/ERP_CUST_AZ12.csv
--     /Volumes/bikemart/bronze/raw_files/ERP_LOC_A101.csv
--     /Volumes/bikemart/bronze/raw_files/ERP_PX_CAT_G1V2.csv
--   via Catalog Explorer > bikemart > bronze > Volumes > raw_files > Upload,
--   or `databricks fs cp <local-file> dbfs:/Volumes/bikemart/bronze/raw_files/`.
--
-- Naming: catalog "bikemart" replaces the 3 MySQL databases with 3 schemas
--   (bronze / silver / gold) in one Unity Catalog catalog. Table names are
--   unchanged from the MySQL version. Change the catalog name below (find
--   and replace "bikemart.") if you'd rather use your own.
--
-- read_files() is the modern Databricks SQL way to read files directly in a
-- CREATE TABLE AS SELECT, no separate COPY INTO or notebook step needed.
-- =============================================================================

CREATE CATALOG IF NOT EXISTS bikemart;
CREATE SCHEMA IF NOT EXISTS bikemart.bronze;
CREATE VOLUME IF NOT EXISTS bikemart.bronze.raw_files;

CREATE OR REPLACE TABLE bikemart.bronze.crm_cust_info AS
SELECT * FROM read_files(
    '/Volumes/bikemart/bronze/raw_files/crm_cust_info.csv',
    format => 'csv', header => true
);

CREATE OR REPLACE TABLE bikemart.bronze.crm_prd_info AS
SELECT * FROM read_files(
    '/Volumes/bikemart/bronze/raw_files/crm_prd_info.csv',
    format => 'csv', header => true
);

CREATE OR REPLACE TABLE bikemart.bronze.crm_sales_details AS
SELECT * FROM read_files(
    '/Volumes/bikemart/bronze/raw_files/crm_sales_details.csv',
    format => 'csv', header => true
);

CREATE OR REPLACE TABLE bikemart.bronze.erp_cust_az12 AS
SELECT * FROM read_files(
    '/Volumes/bikemart/bronze/raw_files/ERP_CUST_AZ12.csv',
    format => 'csv', header => true
);

CREATE OR REPLACE TABLE bikemart.bronze.erp_loc_a101 AS
SELECT * FROM read_files(
    '/Volumes/bikemart/bronze/raw_files/ERP_LOC_A101.csv',
    format => 'csv', header => true
);

CREATE OR REPLACE TABLE bikemart.bronze.erp_px_cat_g1v2 AS
SELECT * FROM read_files(
    '/Volumes/bikemart/bronze/raw_files/ERP_PX_CAT_G1V2.csv',
    format => 'csv', header => true
);
