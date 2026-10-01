/* =====================================================================================
   L05_cloning_time_travel_retention.sql      role: SYSADMIN   edition: any (90-day TT = Enterprise)
   trial: yes      Prereq: core done + one dbt build (dev target -> DEV_MARTS)
   Topics: zero-copy cloning, Time Travel (AT / BEFORE), UNDROP, retention settings,
           permanent vs transient vs temporary, Fail-safe, storage cost of each
   ===================================================================================== */
USE ROLE SYSADMIN;
USE WAREHOUSE WM_TRANSFORM_WH;

/* ---------------------------------------------------------------------------------
   Data lifecycle of a micro-partition that gets changed/dropped:

     current data ──► Time Travel (DATA_RETENTION_TIME_IN_DAYS) ──► Fail-safe (7 days) ──► gone
                      you can query/restore it                      only Snowflake Support,
                                                                    permanent tables only

     table type  | Time Travel        | Fail-safe | lives until
     ------------+--------------------+-----------+-------------------
     PERMANENT   | 0-1 (Std) / 0-90   | 7 days    | dropped
     TRANSIENT   | 0-1                | none      | dropped
     TEMPORARY   | 0-1                | none      | session ends
   --------------------------------------------------------------------------------- */

-- 1. Retention settings (inherit account > database > schema > table; lowest level wins)
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN ACCOUNT;
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE WM_MICRO.RAW.OMS_TRANSACTION;
ALTER TABLE WM_MICRO.RAW.OMS_TRANSACTION SET DATA_RETENTION_TIME_IN_DAYS = 1;
-- Enterprise: ALTER DATABASE WM_MICRO SET DATA_RETENTION_TIME_IN_DAYS = 30;
-- Enterprise: ALTER ACCOUNT SET MIN_DATA_RETENTION_TIME_IN_DAYS = 7;   -- floor nobody can go below

-- 2. Time Travel queries
USE SCHEMA WM_MICRO.DEV_MARTS;
SELECT COUNT(*) FROM FACT_TRANSACTION;
SELECT COUNT(*) FROM FACT_TRANSACTION AT (OFFSET => -60*5);                         -- 5 minutes ago
SELECT COUNT(*) FROM FACT_TRANSACTION AT (TIMESTAMP => DATEADD('minute', -5, CURRENT_TIMESTAMP()));

-- 3. "Oops" recovery with BEFORE(STATEMENT)
CREATE OR REPLACE TABLE WM_MICRO.SCRATCH.TXN_COPY AS SELECT * FROM FACT_TRANSACTION;
DELETE FROM WM_MICRO.SCRATCH.TXN_COPY WHERE txn_type_code = 'BUY';           -- the mistake
SET OOPS_QID = LAST_QUERY_ID();
SELECT COUNT(*) FROM WM_MICRO.SCRATCH.TXN_COPY;                                -- rows gone
INSERT INTO WM_MICRO.SCRATCH.TXN_COPY
SELECT * FROM WM_MICRO.SCRATCH.TXN_COPY BEFORE (STATEMENT => $OOPS_QID)
WHERE txn_type_code = 'BUY';                                                  -- put them back
SELECT COUNT(*) FROM WM_MICRO.SCRATCH.TXN_COPY;

-- 4. DROP / UNDROP (table, schema, database)
DROP TABLE WM_MICRO.SCRATCH.TXN_COPY;
SHOW TABLES HISTORY LIKE 'TXN_COPY' IN SCHEMA WM_MICRO.SCRATCH;               -- see dropped_on
UNDROP TABLE WM_MICRO.SCRATCH.TXN_COPY;
-- If a new table with the same name exists, rename it first, then UNDROP.

-- 5. Zero-copy CLONE: metadata-only copy, instant, no extra storage until data diverges
CREATE OR REPLACE TABLE WM_MICRO.SCRATCH.FACT_TXN_CLONE CLONE FACT_TRANSACTION;
CREATE OR REPLACE SCHEMA WM_MICRO.DEV_MARTS_BACKUP CLONE WM_MICRO.DEV_MARTS;   -- whole schema
CREATE OR REPLACE DATABASE WM_MICRO_QA CLONE WM_MICRO;                          -- full environment for QA

-- Clone + Time Travel: the table as it was before the last dbt run
CREATE OR REPLACE TABLE WM_MICRO.SCRATCH.FACT_TXN_1H_AGO CLONE FACT_TRANSACTION AT (OFFSET => -60*60);

-- What a clone does / doesn't take with it - check for yourself:
SHOW TASKS   IN DATABASE WM_MICRO_QA;      -- cloned tasks are SUSPENDED
SHOW STREAMS IN DATABASE WM_MICRO_QA;      -- streams cloned; unconsumed records in the clone are not readable
SHOW PIPES   IN DATABASE WM_MICRO_QA;
SHOW STAGES  IN DATABASE WM_MICRO_QA;
-- Grants on the source object are NOT copied by default (CLONE ... COPY GRANTS for tables).

-- dbt macro version for CI / dev refresh:
--   dbt run-operation clone_schema --args '{source_schema: MARTS, target_schema: DEV_MARTS}'

-- 6. Temporary vs transient
CREATE TEMPORARY TABLE TMP_SESSION_ONLY AS SELECT 1 AS x;            -- disappears at logout
CREATE TRANSIENT TABLE WM_MICRO.SCRATCH.TRANSIENT_DEMO AS SELECT 1 AS x;
SHOW TABLES LIKE '%DEMO' IN SCHEMA WM_MICRO.SCRATCH;                 -- kind = TRANSIENT

-- 7. What is Time Travel / Fail-safe costing me? (ACCOUNT_USAGE has ~2h latency)
SELECT table_schema, table_name, is_transient,
       ROUND(active_bytes / POWER(1024, 2), 2)       AS active_mb,
       ROUND(time_travel_bytes / POWER(1024, 2), 2)  AS time_travel_mb,
       ROUND(failsafe_bytes / POWER(1024, 2), 2)     AS failsafe_mb,
       ROUND(retained_for_clone_bytes / POWER(1024, 2), 2) AS clone_retained_mb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'WM_MICRO' AND deleted = FALSE
ORDER BY active_bytes DESC;

-- Cleanup
DROP DATABASE IF EXISTS WM_MICRO_QA;
DROP SCHEMA   IF EXISTS WM_MICRO.DEV_MARTS_BACKUP;
