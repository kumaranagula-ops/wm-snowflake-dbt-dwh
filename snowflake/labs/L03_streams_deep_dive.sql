/* =====================================================================================
   L03_streams_deep_dive.sql                  role: SYSADMIN   edition: any   trial: yes
   Prereq: core/07 done.
   Topics: standard vs append-only streams, METADATA$ columns, what an UPDATE looks like,
           consuming vs peeking, offsets & transactions, streams on views, CHANGES clause,
           staleness
   ===================================================================================== */
USE ROLE SYSADMIN;
USE WAREHOUSE WM_LOAD_WH;
USE SCHEMA WM_MICRO.SCRATCH;

-- 1. Playground table + both stream types on it
CREATE OR REPLACE TABLE ACCT_BAL (account_id NUMBER, balance NUMBER(18,2));
CREATE OR REPLACE STREAM S_STANDARD ON TABLE ACCT_BAL;                     -- I / U / D
CREATE OR REPLACE STREAM S_APPEND   ON TABLE ACCT_BAL APPEND_ONLY = TRUE;  -- I only

INSERT INTO ACCT_BAL VALUES (1, 100), (2, 200);
UPDATE ACCT_BAL SET balance = 150 WHERE account_id = 1;
DELETE FROM ACCT_BAL WHERE account_id = 2;

-- Standard stream shows the NET change since its offset:
--   account 1: one INSERT (inserted & updated within the window -> just the latest version)
--   account 2: nothing (inserted then deleted -> nets to zero)
SELECT *, METADATA$ACTION, METADATA$ISUPDATE, METADATA$ROW_ID FROM S_STANDARD;
-- Append-only stream ignores updates/deletes: shows both original inserts
SELECT *, METADATA$ACTION FROM S_APPEND;

-- 2. Consume the standard stream (offset moves on COMMIT of a DML that reads it)
CREATE OR REPLACE TABLE ACCT_BAL_HIST (account_id NUMBER, balance NUMBER(18,2), action VARCHAR, is_update BOOLEAN, captured_at TIMESTAMP_NTZ);
INSERT INTO ACCT_BAL_HIST SELECT account_id, balance, METADATA$ACTION, METADATA$ISUPDATE, CURRENT_TIMESTAMP() FROM S_STANDARD;
SELECT COUNT(*) FROM S_STANDARD;      -- 0 now

-- 3. Now an UPDATE on an existing row = DELETE (old) + INSERT (new), both ISUPDATE = TRUE
UPDATE ACCT_BAL SET balance = 175 WHERE account_id = 1;
SELECT *, METADATA$ACTION, METADATA$ISUPDATE FROM S_STANDARD;

-- 4. Transactions: inside an explicit transaction, the stream is repeatable-read
BEGIN;
  INSERT INTO ACCT_BAL_HIST SELECT account_id, balance, METADATA$ACTION, METADATA$ISUPDATE, CURRENT_TIMESTAMP() FROM S_STANDARD;
  SELECT COUNT(*) FROM S_STANDARD;    -- still shows rows until COMMIT
ROLLBACK;                              -- offset NOT advanced
SELECT COUNT(*) FROM S_STANDARD;      -- rows are still there

-- 5. The pipeline's audit stream on RAW (independent from the RT one)
SELECT _source_file, COUNT(*) FROM WM_MICRO.RAW.STRM_OMS_TRANSACTION_AUDIT GROUP BY 1;

-- 6. Stream on a VIEW (the view must be a simple projection/filter/UNION ALL; change tracking on base tables)
CREATE OR REPLACE VIEW V_BIG_BAL AS SELECT * FROM ACCT_BAL WHERE balance > 100;
CREATE OR REPLACE STREAM S_VIEW ON VIEW V_BIG_BAL;

-- 7. CHANGES clause: stream-like query WITHOUT creating a stream (needs CHANGE_TRACKING = TRUE)
ALTER TABLE ACCT_BAL SET CHANGE_TRACKING = TRUE;
SELECT * FROM ACCT_BAL CHANGES (INFORMATION => DEFAULT) AT (OFFSET => -60*10);
SELECT * FROM WM_MICRO.RAW.OMS_TRANSACTION CHANGES (INFORMATION => APPEND_ONLY)
  AT (OFFSET => -60*60) LIMIT 10;

-- 8. Staleness
SHOW STREAMS IN SCHEMA WM_MICRO.SCRATCH;   -- columns: stale, stale_after, mode
DESCRIBE STREAM S_STANDARD;
-- A stream becomes stale if not consumed within the source table's retention period
-- (Snowflake extends retention up to MAX_DATA_EXTENSION_TIME_IN_DAYS, default 14) -> recreate it.
