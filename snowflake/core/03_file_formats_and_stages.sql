/* =====================================================================================
   03_file_formats_and_stages.sql            run as: SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   A STAGE is a location files sit in before COPY INTO loads them (or after unloading).

     Stage type            Where the files live              Created with
     --------------------  --------------------------------  -------------------------------
     User stage   @~       per user, internal                 automatic
     Table stage  @%TBL    per table, internal                automatic
     Named internal @STG   Snowflake-managed storage          CREATE STAGE (this file)
     Named external @STG   your S3 / Azure Blob / GCS bucket  CREATE STAGE ... URL= + STORAGE INTEGRATION
                                                              (see labs/L02_snowpipe_external_s3.sql)

   A FILE FORMAT tells COPY how to parse the files (CSV, JSON, PARQUET, AVRO, ORC, XML).
   ===================================================================================== */

USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.UTIL;

-- ---------------------------------------------------------------- file formats
CREATE OR REPLACE FILE FORMAT FF_CSV
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_DELIMITER = ','
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = FALSE                      -- keep raw exactly as received; staging cleans it
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
  ENCODING = 'UTF8'
  COMPRESSION = AUTO                      -- PUT gzips files; AUTO detects it
  COMMENT = 'Standard CSV with header row';

CREATE OR REPLACE FILE FORMAT FF_JSON_ARRAY
  TYPE = JSON
  STRIP_OUTER_ARRAY = TRUE                -- [ {...}, {...} ]  -> one row per element
  COMMENT = 'JSON file that is one big array';

CREATE OR REPLACE FILE FORMAT FF_NDJSON
  TYPE = JSON                             -- newline-delimited: one object per line
  COMMENT = 'Newline-delimited JSON';

CREATE OR REPLACE FILE FORMAT FF_PARQUET
  TYPE = PARQUET
  COMMENT = 'Parquet for unload / INFER_SCHEMA demos';

CREATE OR REPLACE FILE FORMAT FF_CSV_UNLOAD
  TYPE = CSV
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  COMPRESSION = GZIP
  NULL_IF = ()
  COMMENT = 'CSV for extracts sent to downstream teams';

-- ---------------------------------------------------------------- named internal stages
CREATE STAGE IF NOT EXISTS STG_LANDING
  DIRECTORY = (ENABLE = TRUE)             -- directory table: SELECT * FROM DIRECTORY(@STG_LANDING)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Inbound files from all source systems: <system>/<entity>/<file>';

CREATE STAGE IF NOT EXISTS STG_EXPORT
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Outbound extracts produced by COPY INTO @stage (unloading)';

/* ---------------------------------------------------------------------------------
   Upload files (from the repo root, on your laptop):

     ./scripts/upload_batch.sh batch_1          (uses Snowflake CLI `snow sql` + PUT)

   or one by one in SnowSQL / snow sql:
     PUT file:///full/path/data/batch_1/oms/transaction/*.csv @WM_MICRO.UTIL.STG_LANDING/oms/transaction/ AUTO_COMPRESS = TRUE;

   Snowsight also lets you upload files to a stage from the UI (Data > Databases > stage > + Files).
   --------------------------------------------------------------------------------- */

-- After uploading:
LIST @STG_LANDING;
ALTER STAGE STG_LANDING REFRESH;                         -- refresh directory table
SELECT relative_path, size, last_modified FROM DIRECTORY(@STG_LANDING) ORDER BY 1;

-- Query staged files BEFORE loading them (schema-on-read peek)
SELECT $1, $2, $3, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER
FROM @STG_LANDING/oms/transaction/ (FILE_FORMAT => 'FF_CSV')
LIMIT 10;

SELECT $1:ticker::STRING AS ticker, $1:listings AS listings
FROM @STG_LANDING/mkt/security/ (FILE_FORMAT => 'FF_JSON_ARRAY');
