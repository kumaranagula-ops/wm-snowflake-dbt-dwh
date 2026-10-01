/* =====================================================================================
   06_tasks_eod_graph.sql                     run as: SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   A TASK GRAPH (DAG) that runs the end-of-day ingestion inside Snowflake - no external
   scheduler needed for loading.

                        TSK_EOD_ROOT  (CRON 19:00 IST Mon-Fri, opens CNTL_BATCH_RUN row)
                       /      |       \
            TSK_LOAD_CRM  TSK_LOAD_CORE  TSK_LOAD_MKT (serverless)
                       \      /
                     TSK_LOAD_OMS        (2 predecessors: waits for CRM and CORE)

            TSK_EOD_FINALIZER  (FINALIZE = root: always runs at the end, even on failure,
                                closes the CNTL_BATCH_RUN row)

   dbt then runs AFTER the graph (GitHub Actions cron, Airflow, dbt Cloud ...). The
   CNTL_BATCH_RUN table lets dbt (or a person) see that today's load finished.

   Task types shown here:
     * scheduled with CRON + time zone            (root)
     * warehouse-backed (WAREHOUSE = ...)          (CRM, CORE, OMS, finalizer)
     * serverless (no WAREHOUSE, Snowflake sizes)  (MKT)
     * child tasks with AFTER, multi-predecessor   (OMS)
     * finalizer task                              (FINALIZER)
     * stream-triggered task -> see 07_streams_realtime.sql
   ===================================================================================== */

USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.UTIL;

-- Root -----------------------------------------------------------------------------
CREATE OR REPLACE TASK TSK_EOD_ROOT
  WAREHOUSE = WM_LOAD_WH
  SCHEDULE  = 'USING CRON 0 19 * * MON-FRI Asia/Kolkata'
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3        -- auto-suspend a graph that keeps failing
  TASK_AUTO_RETRY_ATTEMPTS = 1               -- retry the whole graph once on failure
  USER_TASK_TIMEOUT_MS = 3600000             -- 1 hour
  COMMENT = 'EOD ingestion root: opens the batch'
AS
  INSERT INTO WM_MICRO.CNTL.CNTL_BATCH_RUN (batch_id, pipeline_name, target_name, invoked_by, status, started_at)
  SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID'),
         'EOD_INGEST', 'SNOWFLAKE', 'TASK:TSK_EOD_ROOT', 'RUNNING', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

-- Children ---------------------------------------------------------------------------
CREATE OR REPLACE TASK TSK_LOAD_CRM
  WAREHOUSE = WM_LOAD_WH
  AFTER TSK_EOD_ROOT
AS
EXECUTE IMMEDIATE $$
BEGIN
    LET b VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
    CALL WM_MICRO.UTIL.SP_LOAD_SOURCE('CRM', :b);
END;
$$;

CREATE OR REPLACE TASK TSK_LOAD_CORE
  WAREHOUSE = WM_LOAD_WH
  AFTER TSK_EOD_ROOT
AS
EXECUTE IMMEDIATE $$
BEGIN
    LET b VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
    CALL WM_MICRO.UTIL.SP_LOAD_SOURCE('CORE', :b);
END;
$$;

-- Serverless: no WAREHOUSE. Snowflake picks/adjusts compute and bills per-second
CREATE OR REPLACE TASK TSK_LOAD_MKT
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
  AFTER TSK_EOD_ROOT
AS
EXECUTE IMMEDIATE $$
BEGIN
    LET b VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
    CALL WM_MICRO.UTIL.SP_LOAD_SOURCE('MKT', :b);
END;
$$;

-- Two predecessors: trades only load once accounts & clients are in
CREATE OR REPLACE TASK TSK_LOAD_OMS
  WAREHOUSE = WM_LOAD_WH
  AFTER TSK_LOAD_CRM, TSK_LOAD_CORE
AS
EXECUTE IMMEDIATE $$
BEGIN
    LET b VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
    CALL WM_MICRO.UTIL.SP_LOAD_SOURCE('OMS', :b);
END;
$$;

-- Finalizer: runs after all other tasks finish OR fail -> always closes the batch
CREATE OR REPLACE TASK TSK_EOD_FINALIZER
  WAREHOUSE = WM_LOAD_WH
  FINALIZE = TSK_EOD_ROOT
AS
EXECUTE IMMEDIATE $$
BEGIN
    LET b VARCHAR := SYSTEM$TASK_RUNTIME_INFO('CURRENT_TASK_GRAPH_RUN_GROUP_ID');
    UPDATE WM_MICRO.CNTL.CNTL_BATCH_RUN r
       SET status       = IFF(a.bad_files > 0, 'COMPLETED_WITH_ERRORS', 'SUCCEEDED'),
           ended_at     = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
           files_loaded = a.files,
           rows_loaded  = a.rows_loaded
      FROM (SELECT COUNT_IF(status <> 'PROC_ERROR')                         AS files,
                   COALESCE(SUM(rows_loaded), 0)                            AS rows_loaded,
                   COUNT_IF(status = 'PROC_ERROR' OR error_count > 0)       AS bad_files
              FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT
             WHERE batch_id = :b) a
     WHERE r.batch_id = :b;
END;
$$;

/* ---------------------------------------------------------------------------------
   Turn it on.
   Tasks are created SUSPENDED. Children/finalizer must be resumed before the root.
   We keep the ROOT suspended (no daily runs, no cost) and trigger it by hand.
   --------------------------------------------------------------------------------- */
ALTER TASK TSK_EOD_FINALIZER RESUME;
ALTER TASK TSK_LOAD_OMS      RESUME;
ALTER TASK TSK_LOAD_MKT      RESUME;
ALTER TASK TSK_LOAD_CORE     RESUME;
ALTER TASK TSK_LOAD_CRM      RESUME;
-- ALTER TASK TSK_EOD_ROOT RESUME;          -- uncomment to run every weekday at 19:00 IST
-- SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('WM_MICRO.UTIL.TSK_EOD_ROOT');   -- resumes the whole graph in one go

EXECUTE TASK TSK_EOD_ROOT;                    -- manual run of the whole graph now

/* ---------------------------------------------------------------------------------
   Monitor (give it ~1 minute)
   --------------------------------------------------------------------------------- */
SELECT name, state, scheduled_time, completed_time, error_message, graph_run_group_id
FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.TASK_HISTORY(
       SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP())))
ORDER BY scheduled_time DESC;

SELECT * FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.CURRENT_TASK_GRAPHS());   -- running now
SELECT * FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.COMPLETE_TASK_GRAPHS());  -- finished

SELECT * FROM WM_MICRO.CNTL.CNTL_BATCH_RUN ORDER BY started_at DESC;
SELECT * FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT ORDER BY audit_id DESC;

SHOW TASKS IN SCHEMA WM_MICRO.UTIL;
-- Snowsight: Monitoring > Task History shows the graph visually.
