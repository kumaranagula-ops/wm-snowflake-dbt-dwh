/* =====================================================================================
   L04_tasks_deep_dive.sql                    role: SYSADMIN   edition: any   trial: yes
   Prereq: core/06-07 done.
   Topics: schedule types, serverless vs warehouse, WHEN conditions, triggered tasks,
           return values between tasks, task config, retries, monitoring, ownership
   ===================================================================================== */
USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.SCRATCH;

-- 1. Schedule flavours ------------------------------------------------------------
CREATE OR REPLACE TASK T_EVERY_5_MIN   WAREHOUSE = WM_LOAD_WH SCHEDULE = '5 MINUTE' AS SELECT 1;
CREATE OR REPLACE TASK T_CRON_MONTHEND WAREHOUSE = WM_LOAD_WH
  SCHEDULE = 'USING CRON 0 22 L * * Asia/Kolkata'          -- last day of month, 22:00 IST
AS SELECT 1;

-- 2. Serverless task, Snowflake adjusts size between runs to meet the schedule
CREATE OR REPLACE TASK T_SERVERLESS
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  SCHEDULE = '60 MINUTE'
AS SELECT 1;
--   Serverless: billed per second of compute actually used, no idle cost,
--               good for short frequent jobs.
--   Warehouse : you control size, can share a warehouse already running; min 60 s billing on resume.

-- 3. Conditional run: WHEN is evaluated in cloud services, no warehouse if FALSE
CREATE OR REPLACE TASK T_WHEN_STREAM WAREHOUSE = WM_LOAD_WH SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('WM_MICRO.RAW.STRM_OMS_TRANSACTION_AUDIT')
AS SELECT COUNT(*) FROM WM_MICRO.RAW.STRM_OMS_TRANSACTION_AUDIT;

-- 4. Passing a value from parent to child
CREATE OR REPLACE TASK T_PARENT WAREHOUSE = WM_LOAD_WH SCHEDULE = '60 MINUTE'
  CONFIG = $${"environment": "dev", "min_rows": 1}$$       -- graph-level config JSON
AS
EXECUTE IMMEDIATE $$
DECLARE
    n INTEGER;
BEGIN
    SELECT COUNT(*) INTO :n FROM WM_MICRO.RAW.OMS_TRANSACTION;
    LET v VARCHAR := 'rows_seen=' || n;
    CALL SYSTEM$SET_RETURN_VALUE(:v);
END;
$$;

CREATE OR REPLACE TABLE TASK_LOG (parent_value VARCHAR, env VARCHAR, logged_at TIMESTAMP_LTZ);

CREATE OR REPLACE TASK T_CHILD WAREHOUSE = WM_LOAD_WH AFTER T_PARENT
AS
  INSERT INTO WM_MICRO.SCRATCH.TASK_LOG
  SELECT SYSTEM$GET_PREDECESSOR_RETURN_VALUE(),
         SYSTEM$GET_TASK_GRAPH_CONFIG('environment'),
         CURRENT_TIMESTAMP();

ALTER TASK T_CHILD RESUME;
EXECUTE TASK T_PARENT;            -- runs even though the root itself stays suspended
-- wait ~1 min
SELECT * FROM TASK_LOG;

-- 5. Monitoring
SELECT name, state, error_code, error_message, scheduled_time, query_start_time, completed_time, attempt_number
FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()), RESULT_LIMIT => 100))
ORDER BY scheduled_time DESC;
-- Account-wide history (365 days): SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
-- Serverless cost: SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY

-- 6. Operating tasks
-- ALTER TASK <t> SUSPEND | RESUME;  ALTER TASK <t> SET SCHEDULE = '...';
-- Changing a child requires the ROOT to be suspended first.
-- Ownership: the task runs with the privileges of its OWNER role (not the user who resumed it).
-- Tasks cloned with a database/schema are created SUSPENDED.

-- Cleanup (these are demos; don't leave them running)
DROP TASK IF EXISTS T_EVERY_5_MIN; DROP TASK IF EXISTS T_CRON_MONTHEND; DROP TASK IF EXISTS T_SERVERLESS;
DROP TASK IF EXISTS T_WHEN_STREAM; DROP TASK IF EXISTS T_CHILD;       DROP TASK IF EXISTS T_PARENT;
