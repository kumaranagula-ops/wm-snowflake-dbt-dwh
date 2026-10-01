/* =====================================================================================
   L02_snowpipe_external_s3.sql     role: ACCOUNTADMIN/SYSADMIN   edition: any
   trial: TEMPLATE - needs an AWS account + S3 bucket + IAM role you control.
   Topics: storage integration, external stage, Snowpipe auto-ingest (S3 -> SQS),
           pipe monitoring, external tables, insert-only streams, Iceberg (note)
   ===================================================================================== */

-- Replace these
SET S3_URL       = 's3://<your-bucket>/wm/landing/';
SET AWS_ROLE_ARN = 'arn:aws:iam::<account-id>:role/<snowflake-access-role>';

/* 1. STORAGE INTEGRATION: Snowflake assumes an IAM role in YOUR account - no keys stored.
      Create it, then copy STORAGE_AWS_IAM_USER_ARN + STORAGE_AWS_EXTERNAL_ID from DESC into
      the IAM role's trust policy. */
USE ROLE ACCOUNTADMIN;
CREATE STORAGE INTEGRATION IF NOT EXISTS WM_S3_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = $AWS_ROLE_ARN
  STORAGE_ALLOWED_LOCATIONS = ($S3_URL);
DESC INTEGRATION WM_S3_INT;
GRANT USAGE ON INTEGRATION WM_S3_INT TO ROLE SYSADMIN;

-- 2. External stage
USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.UTIL;
CREATE OR REPLACE STAGE STG_S3_LANDING
  URL = $S3_URL
  STORAGE_INTEGRATION = WM_S3_INT
  FILE_FORMAT = FF_CSV;
LIST @STG_S3_LANDING;

/* 3. SNOWPIPE (auto-ingest)
      S3 "ObjectCreated" event -> SQS queue owned by Snowflake -> pipe runs its COPY.
      Serverless (no warehouse), billed per file + compute; latency ~1 minute. */
CREATE OR REPLACE PIPE WM_MICRO.UTIL.PIPE_OMS_TRANSACTION
  AUTO_INGEST = TRUE
  COMMENT = 'Continuously loads trade files dropped into s3://.../oms/transaction/'
AS
COPY INTO WM_MICRO.RAW.OMS_TRANSACTION
    (txn_id, account_id, txn_type, ticker, quantity, price, amount, fees, channel, order_type, txn_ts,
     settle_date, status, _source_file, _file_row_number, _file_last_modified, _batch_id)
FROM (SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,
             METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$FILE_LAST_MODIFIED, 'SNOWPIPE'
      FROM @WM_MICRO.UTIL.STG_S3_LANDING/oms/transaction/)
FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV');

SHOW PIPES IN SCHEMA WM_MICRO.UTIL;     -- copy notification_channel (an SQS ARN)
-- In AWS: S3 bucket > Properties > Event notifications > All object create events
--         prefix wm/landing/oms/transaction/ > destination SQS queue = notification_channel

SELECT SYSTEM$PIPE_STATUS('WM_MICRO.UTIL.PIPE_OMS_TRANSACTION');   -- executionState, pendingFileCount
ALTER PIPE WM_MICRO.UTIL.PIPE_OMS_TRANSACTION REFRESH;              -- queue files already in the bucket (last 7 days)
-- ALTER PIPE ... SET PIPE_EXECUTION_PAUSED = TRUE;                 -- pause / resume

SELECT * FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.PIPE_USAGE_HISTORY(
    DATE_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()), PIPE_NAME => 'WM_MICRO.UTIL.PIPE_OMS_TRANSACTION'));
SELECT * FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'WM_MICRO.RAW.OMS_TRANSACTION', START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())))
WHERE pipe_name IS NOT NULL;

/* Pipes on INTERNAL stages cannot auto-ingest (no cloud event); a client calls the Snowpipe
   REST API (insertFiles) instead. Snowpipe default ON_ERROR is SKIP_FILE.
   Snowpipe Streaming: rows (not files) via the Kafka connector / SDK, lowest latency. */

/* 4. EXTERNAL TABLE: query files in S3 without loading them (read-only, slower, cheap storage).
      VALUE is a VARIANT per row; columns are expressions on it. */
CREATE OR REPLACE EXTERNAL TABLE WM_MICRO.RAW.EXT_MKT_PRICE (
    ticker      VARCHAR AS (VALUE:c1::VARCHAR),
    price_date  DATE    AS (TRY_TO_DATE(VALUE:c2::VARCHAR)),
    close_price NUMBER(18,4) AS (TRY_TO_NUMBER(VALUE:c6::VARCHAR, 18, 4))
)
LOCATION = @WM_MICRO.UTIL.STG_S3_LANDING/mkt/price/
FILE_FORMAT = (FORMAT_NAME = 'WM_MICRO.UTIL.FF_CSV')
AUTO_REFRESH = TRUE;                    -- metadata refreshed by the same S3 events
ALTER EXTERNAL TABLE WM_MICRO.RAW.EXT_MKT_PRICE REFRESH;
SELECT * FROM WM_MICRO.RAW.EXT_MKT_PRICE LIMIT 10;

-- 5. INSERT_ONLY stream: the only stream type allowed on external tables
CREATE OR REPLACE STREAM WM_MICRO.RAW.STRM_EXT_MKT_PRICE
  ON EXTERNAL TABLE WM_MICRO.RAW.EXT_MKT_PRICE INSERT_ONLY = TRUE;

/* 6. Iceberg tables (open table format, data in your bucket, Snowflake as engine/catalog):
      CREATE ICEBERG TABLE ... CATALOG = 'SNOWFLAKE' EXTERNAL_VOLUME = '<vol>' BASE_LOCATION = '...';
      Useful when Spark/other engines must read the same tables. */

-- Cleanup
-- DROP PIPE WM_MICRO.UTIL.PIPE_OMS_TRANSACTION; DROP EXTERNAL TABLE WM_MICRO.RAW.EXT_MKT_PRICE;
