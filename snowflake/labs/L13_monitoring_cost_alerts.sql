/* =====================================================================================
   L13_monitoring_cost_alerts.sql             role: ACCOUNTADMIN   edition: any   trial: yes
   Topics: ACCOUNT_USAGE vs INFORMATION_SCHEMA, credits by warehouse, cost by query_tag,
           storage, serverless features cost, failed loads/tasks, alerts + notifications,
           budgets
   ===================================================================================== */
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WM_BI_WH;

/* INFORMATION_SCHEMA (per database): real-time, short history (7-14 days), only objects you can see
   SNOWFLAKE.ACCOUNT_USAGE: whole account, 365 days, 45 min - 3 h latency, includes dropped objects */

-- 1. Credits per warehouse per day
SELECT TO_DATE(start_time) AS day, warehouse_name, ROUND(SUM(credits_used), 3) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC;

-- 2. Which dbt models are slowest? (profiles set query_tag = dbt_wm_micro / _ci / _prod)
SELECT query_tag, LEFT(query_text, 100) AS sql, total_elapsed_time / 1000 AS secs, bytes_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_tag LIKE 'dbt_wm_micro%' AND start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY total_elapsed_time DESC LIMIT 20;

-- 3. Serverless features (tasks, Snowpipe, clustering, DT, search optimization ...)
SELECT service_type, ROUND(SUM(credits_used), 3) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 2 DESC;

-- 4. Storage over time (database + stage + fail-safe)
SELECT usage_date, ROUND(average_database_bytes / POWER(1024, 3), 4) AS db_gb,
       ROUND(average_failsafe_bytes / POWER(1024, 3), 4) AS failsafe_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE database_name = 'WM_MICRO' ORDER BY usage_date DESC LIMIT 30;

-- 5. Operational health: failed tasks and partially loaded files
SELECT name, state, error_message, scheduled_time
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE state = 'FAILED' AND scheduled_time >= DATEADD('day', -7, CURRENT_TIMESTAMP());

SELECT * FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT WHERE error_count > 0 OR status = 'PROC_ERROR';
SELECT * FROM WM_MICRO.CNTL.CNTL_DQ_RESULT WHERE status IN ('fail', 'warn', 'error') ORDER BY executed_at DESC;

-- 6. ALERT: Snowflake checks a condition on a schedule and acts when it returns rows.
--    Email notifications need a verified email address on your Snowflake user.
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS WM_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('<your-verified-email@example.com>');
GRANT USAGE ON INTEGRATION WM_EMAIL_INT TO ROLE SYSADMIN;
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
CREATE OR REPLACE ALERT WM_MICRO.UTIL.ALRT_LOAD_ERRORS
  WAREHOUSE = WM_LOAD_WH
  SCHEDULE  = 'USING CRON 30 19 * * MON-FRI Asia/Kolkata'
  IF (EXISTS (
        SELECT 1 FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT
        WHERE (error_count > 0 OR status = 'PROC_ERROR')
          AND audited_at > SNOWFLAKE.ALERT.LAST_SUCCESSFUL_SCHEDULED_TIME()))
  THEN
    CALL SYSTEM$SEND_EMAIL('WM_EMAIL_INT', '<your-verified-email@example.com>',
                           'WM EOD load errors', 'Check WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT');
-- ALTER ALERT WM_MICRO.UTIL.ALRT_LOAD_ERRORS RESUME;      -- alerts are created suspended
-- SELECT * FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.ALERT_HISTORY());

/* 7. Budgets (Snowsight > Admin > Cost Management): monthly spending limit with
      notifications for the account or a group of objects - complements resource monitors,
      which only cover warehouses. */
