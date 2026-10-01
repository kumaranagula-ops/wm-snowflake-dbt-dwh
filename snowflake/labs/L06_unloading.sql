/* =====================================================================================
   L06_unloading.sql                          role: SYSADMIN   edition: any   trial: yes
   Prereq: dbt build (dev target -> DEV_MARTS)
   Topics: COPY INTO @stage (unload), formats, SINGLE, MAX_FILE_SIZE, PARTITION BY,
           HEADER, OVERWRITE, GET to laptop, unload to S3, querying unloaded files
   ===================================================================================== */
USE ROLE SYSADMIN;
USE WAREHOUSE WM_TRANSFORM_WH;
USE SCHEMA WM_MICRO.DEV_MARTS;

-- 1. Monthly AUM extract as gzipped CSV (default: multiple files in parallel)
COPY INTO @WM_MICRO.UTIL.STG_EXPORT/client_aum/csv/
FROM (
    SELECT d.month_end_date, c.client_id, c.client_name, c.segment, f.aum_inr
    FROM FACT_CLIENT_AUM_MONTHLY f
    JOIN DIM_CLIENT c ON c.client_key = f.client_key
    JOIN DIM_DATE   d ON d.date_key  = f.month_date_key
)
FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV_UNLOAD')
HEADER = TRUE
OVERWRITE = TRUE;

-- 2. One single file with a fixed name (SINGLE = TRUE; max 5 GB)
COPY INTO @WM_MICRO.UTIL.STG_EXPORT/client_aum/client_aum_latest.csv.gz
FROM (SELECT * FROM FACT_CLIENT_AUM_MONTHLY)
FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV_UNLOAD')
HEADER = TRUE SINGLE = TRUE OVERWRITE = TRUE MAX_FILE_SIZE = 104857600;

-- 3. Parquet, partitioned into folders by month (data-lake style layout)
COPY INTO @WM_MICRO.UTIL.STG_EXPORT/fact_transaction/
FROM (SELECT *, TO_CHAR(txn_date, 'YYYY-MM') AS ym FROM FACT_TRANSACTION)
PARTITION BY ('ym=' || ym)
FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_PARQUET')
HEADER = TRUE;                       -- keeps real column names in Parquet

LIST @WM_MICRO.UTIL.STG_EXPORT;

-- 4. Read back what you unloaded, without loading it
SELECT $1:txn_id::NUMBER AS txn_id, $1:net_cash_flow::NUMBER(18,2) AS net_cash_flow, METADATA$FILENAME
FROM @WM_MICRO.UTIL.STG_EXPORT/fact_transaction/ (FILE_FORMAT => 'WM_MICRO.UTIL.FF_PARQUET')
LIMIT 10;

-- 5. Download to your laptop (SnowSQL / snow CLI, not Snowsight worksheets):
--    snow sql -q "GET @WM_MICRO.UTIL.STG_EXPORT/client_aum/ file://./exports/"

-- 6. Unload straight to S3 (needs the external stage from L02)
-- COPY INTO @WM_MICRO.UTIL.STG_S3_LANDING/exports/aum/ FROM FACT_CLIENT_AUM_MONTHLY
--   FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_PARQUET') HEADER = TRUE;

-- 7. Housekeeping
REMOVE @WM_MICRO.UTIL.STG_EXPORT/client_aum/csv/;
