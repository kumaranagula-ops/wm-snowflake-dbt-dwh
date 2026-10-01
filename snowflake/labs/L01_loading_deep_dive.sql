/* =====================================================================================
   L01_loading_deep_dive.sql                  role: SYSADMIN   edition: any   trial: yes
   Prereq: core/00-05 done, batch_1 uploaded.
   Topics: COPY options, VALIDATION_MODE, VALIDATE(), ON_ERROR, load metadata & FORCE,
           PURGE, table/user stages, INFER_SCHEMA + USING TEMPLATE, MATCH_BY_COLUMN_NAME,
           COPY vs INSERT, LOAD_HISTORY / COPY_HISTORY
   ===================================================================================== */
USE ROLE SYSADMIN;
USE WAREHOUSE WM_LOAD_WH;
USE SCHEMA WM_MICRO.SCRATCH;

-- 1. Dry run: VALIDATION_MODE parses files and returns errors WITHOUT loading.
--    (Not allowed together with a SELECT transformation, so use a plain-shaped table.)
CREATE OR REPLACE TRANSIENT TABLE TXN_PLAIN LIKE WM_MICRO.RAW.OMS_TRANSACTION;
ALTER TABLE TXN_PLAIN DROP COLUMN _source_file, _file_row_number, _file_last_modified, _batch_id, _loaded_at;

COPY INTO TXN_PLAIN FROM @WM_MICRO.UTIL.STG_LANDING/oms/transaction/
  FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV')
  VALIDATION_MODE = RETURN_ERRORS;          -- or RETURN_10_ROWS / RETURN_ALL_ERRORS

-- 2. Make a broken file in the table stage (@%TXN_PLAIN) and see ON_ERROR in action
COPY INTO @%TXN_PLAIN/bad/bad.csv FROM (
    SELECT 'txn_id,account_id' UNION ALL SELECT '1,2,3,4'   -- wrong column count
) FILE_FORMAT = (TYPE = CSV COMPRESSION = NONE FIELD_OPTIONALLY_ENCLOSED_BY = NONE) SINGLE = TRUE HEADER = FALSE OVERWRITE = TRUE;
LIST @%TXN_PLAIN;

COPY INTO TXN_PLAIN FROM @%TXN_PLAIN/bad/
  FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV') ON_ERROR = 'CONTINUE';
SELECT * FROM TABLE(VALIDATE(TXN_PLAIN, JOB_ID => '_last'));   -- rejected rows of the last COPY

-- 3. Load metadata: running the same COPY twice loads 0 files the 2nd time
COPY INTO TXN_PLAIN FROM @WM_MICRO.UTIL.STG_LANDING/oms/transaction/ FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV');
COPY INTO TXN_PLAIN FROM @WM_MICRO.UTIL.STG_LANDING/oms/transaction/ FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV');  -- 0 files
COPY INTO TXN_PLAIN FROM @WM_MICRO.UTIL.STG_LANDING/oms/transaction/ FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV') FORCE = TRUE; -- duplicates!
-- LOAD_UNCERTAIN_FILES = TRUE: load files whose status is unknown (older than 64 days)
-- PURGE = TRUE: delete files from the stage after a successful load
-- SIZE_LIMIT, FILES = ('a.csv','b.csv'), PATTERN = '<regex>' select which files

-- 4. Load history
SELECT file_name, status, row_count, row_parsed, first_error_message, last_load_time
FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.COPY_HISTORY(TABLE_NAME => 'WM_MICRO.SCRATCH.TXN_PLAIN',
                                                     START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())));
-- account-wide (up to 365 days, ~2h latency): SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY

-- 5. INFER_SCHEMA: create a table straight from Parquet/Avro/ORC/CSV file metadata
COPY INTO @WM_MICRO.UTIL.STG_EXPORT/infer_demo/ FROM (SELECT * FROM WM_MICRO.RAW.MKT_PRICE LIMIT 500)
  FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_PARQUET') HEADER = TRUE OVERWRITE = TRUE;

SELECT * FROM TABLE(INFER_SCHEMA(LOCATION => '@WM_MICRO.UTIL.STG_EXPORT/infer_demo/',
                                 FILE_FORMAT => 'WM_MICRO.UTIL.FF_PARQUET'));

CREATE OR REPLACE TABLE PRICE_FROM_PARQUET USING TEMPLATE (
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
    FROM TABLE(INFER_SCHEMA(LOCATION => '@WM_MICRO.UTIL.STG_EXPORT/infer_demo/',
                            FILE_FORMAT => 'WM_MICRO.UTIL.FF_PARQUET')));

COPY INTO PRICE_FROM_PARQUET FROM @WM_MICRO.UTIL.STG_EXPORT/infer_demo/
  FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_PARQUET')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;          -- map by name, not position
SELECT * FROM PRICE_FROM_PARQUET LIMIT 10;

-- 6. User stage @~ (private to you)
-- PUT file:///tmp/anything.csv @~/scratch/;   LIST @~;   REMOVE @~/scratch/;

/* Interview notes
   * COPY INTO = bulk, warehouse compute, best for scheduled batches.
   * Snowpipe  = serverless, event-driven micro-batches (labs/L02).
   * Snowpipe Streaming = row-level, no files (Kafka connector / Java SDK), seconds latency.
   * INSERT ... VALUES is for tiny volumes only - each statement creates micro-partitions. */
