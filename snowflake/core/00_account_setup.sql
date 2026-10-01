/* =====================================================================================
   00_account_setup.sql                      run as: ACCOUNTADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   Creates the compute (warehouses), storage containers (database + schemas) and a cost
   guard-rail (resource monitor) for the WM (wealth management) warehouse.

   Topics: virtual warehouses, auto-suspend/resume, database & schema retention,
           transient schema, resource monitors, task privileges
   ===================================================================================== */

USE ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- 1. Compute: one warehouse per workload, so loads, transforms and BI never
--    queue behind each other and cost is visible per workload.
-- ---------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS WM_LOAD_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ingestion: COPY INTO, Snowpipe-adjacent tasks, stream merges';

CREATE WAREHOUSE IF NOT EXISTS WM_TRANSFORM_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'dbt builds and dynamic table refreshes';

CREATE WAREHOUSE IF NOT EXISTS WM_BI_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Analysts / dashboards';
  -- Enterprise+: MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 3 SCALING_POLICY = 'STANDARD'
  -- (multi-cluster scales OUT for concurrency; a bigger size scales UP for heavy queries)

-- ---------------------------------------------------------------------------
-- 2. Storage: one database, one schema per layer.
--    DATA_RETENTION_TIME_IN_DAYS = Time Travel window (Standard max 1, Enterprise max 90).
--    Permanent objects ALSO get 7 days of Fail-safe after Time Travel ends.
-- ---------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS WM_MICRO
  DATA_RETENTION_TIME_IN_DAYS = 1
  COMMENT = 'Wealth-management mini data warehouse (Snowflake + dbt)';

USE DATABASE WM_MICRO;

CREATE SCHEMA IF NOT EXISTS RAW        COMMENT = 'Landing: files copied 1:1, all VARCHAR + load metadata. Loaded by COPY/Snowpipe, never by dbt';
CREATE SCHEMA IF NOT EXISTS UTIL       COMMENT = 'Stages, file formats, stored procedures, UDFs, EOD task graph';
CREATE SCHEMA IF NOT EXISTS CNTL       COMMENT = 'Control / audit tables (CNTL_*) shared by Snowflake tasks and dbt';
CREATE SCHEMA IF NOT EXISTS RT         COMMENT = 'Near-real-time path: streams + triggered task + dynamic tables';
CREATE SCHEMA IF NOT EXISTS GOVERNANCE COMMENT = 'Tags, masking policies, row access policies';

-- Transient schema: tables inside are transient by default -> no Fail-safe, max 1 day Time Travel.
-- Good for scratch / re-creatable data; cheaper storage.
CREATE TRANSIENT SCHEMA IF NOT EXISTS SCRATCH DATA_RETENTION_TIME_IN_DAYS = 1
  COMMENT = 'Labs / throw-away work area: transient (no Fail-safe), 1 day Time Travel';

-- dbt creates the rest itself: STAGING, INTERMEDIATE, SNAPSHOTS, MARTS, SHARE, REF
-- (or DEV_STAGING, DEV_MARTS ... when running with the dev target).

-- ---------------------------------------------------------------------------
-- 3. Cost guard-rail + task privileges (need ACCOUNTADMIN)
-- ---------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS WM_RM
  WITH CREDIT_QUOTA = 10 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND              -- lets running queries finish
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;   -- kills running queries

ALTER WAREHOUSE WM_LOAD_WH      SET RESOURCE_MONITOR = WM_RM;
ALTER WAREHOUSE WM_TRANSFORM_WH SET RESOURCE_MONITOR = WM_RM;
ALTER WAREHOUSE WM_BI_WH        SET RESOURCE_MONITOR = WM_RM;

-- Task owners need these account-level privileges
GRANT EXECUTE TASK         ON ACCOUNT TO ROLE SYSADMIN;   -- warehouse-backed tasks
GRANT EXECUTE MANAGED TASK ON ACCOUNT TO ROLE SYSADMIN;   -- serverless tasks

-- Check
SHOW WAREHOUSES LIKE 'WM_%';
SHOW SCHEMAS IN DATABASE WM_MICRO;
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN DATABASE WM_MICRO;
