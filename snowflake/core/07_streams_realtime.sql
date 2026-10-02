/* =====================================================================================
   07_streams_realtime.sql                    run as: SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   Near-real-time path that runs NEXT TO the dbt batch path:

     RAW.OMS_TRANSACTION ──(append-only stream)──► triggered task ──MERGE──► RT.INTRADAY_TRADE
                                                                                  │
                                                         dynamic tables (08) ◄────┘

   A STREAM is a change-data-capture bookmark (an offset) on a table/view. Selecting from
   it returns rows changed since the offset, plus:
       METADATA$ACTION    INSERT / DELETE
       METADATA$ISUPDATE  TRUE when the INSERT/DELETE pair represents an UPDATE
       METADATA$ROW_ID    stable row id
   The offset only moves when the stream is read inside a DML statement that COMMITS
   (INSERT/MERGE ... SELECT FROM stream). A plain SELECT does not consume it.

   Stream types
     standard (default)   inserts, updates, deletes          tables, views, dynamic tables
     APPEND_ONLY = TRUE   inserts only (cheaper)             tables, views
     INSERT_ONLY = TRUE   inserts only                       external tables / Iceberg (see labs/L02)
   Each consumer should have its OWN stream - one consumer's MERGE would empty it for the other.
   Staleness: if a stream is not consumed within the table's retention (+ up to 14 days
   extension, MAX_DATA_EXTENSION_TIME_IN_DAYS), it goes STALE and must be recreated.
   ===================================================================================== */

USE ROLE SYSADMIN;
USE WAREHOUSE WM_LOAD_WH;

-- Target table for the intraday feed (typed, de-duplicated) -------------------------
CREATE TABLE IF NOT EXISTS WM_MICRO.RT.INTRADAY_TRADE (
    txn_id          NUMBER        NOT NULL,
    account_id      NUMBER,
    txn_type        VARCHAR(20),
    ticker          VARCHAR(20),
    quantity        NUMBER(18,4),
    signed_quantity NUMBER(18,4),
    price           NUMBER(18,4),
    amount          NUMBER(18,2),
    fees            NUMBER(18,2),
    channel         VARCHAR(20),
    txn_ts          TIMESTAMP_NTZ,
    _source_file    VARCHAR,
    _ingested_at    TIMESTAMP_NTZ,
    _updated_at     TIMESTAMP_NTZ,
    CONSTRAINT pk_intraday_trade PRIMARY KEY (txn_id)
) CHANGE_TRACKING = TRUE;

-- Streams on RAW -------------------------------------------------------------------
-- Consumer 1: the intraday MERGE. SHOW_INITIAL_ROWS = TRUE -> first read also returns rows
-- that already existed when the stream was created (so batch_1 flows through too).
CREATE OR REPLACE STREAM WM_MICRO.RAW.STRM_OMS_TRANSACTION_RT
  ON TABLE WM_MICRO.RAW.OMS_TRANSACTION
  APPEND_ONLY = TRUE
  SHOW_INITIAL_ROWS = TRUE
  COMMENT = 'Consumed by RT.TSK_MERGE_INTRADAY_TRADE';

-- Consumer 2: an independent audit consumer (shows that each consumer needs its own stream)
CREATE OR REPLACE STREAM WM_MICRO.RAW.STRM_OMS_TRANSACTION_AUDIT
  ON TABLE WM_MICRO.RAW.OMS_TRANSACTION
  APPEND_ONLY = TRUE
  COMMENT = 'Read manually in labs/L03_streams_deep_dive.sql';

-- Standard stream on the RT table: sees the UPDATEs the MERGE makes (late corrections)
CREATE OR REPLACE STREAM WM_MICRO.RT.STRM_INTRADAY_TRADE_CHANGES
  ON TABLE WM_MICRO.RT.INTRADAY_TRADE
  COMMENT = 'Standard stream: INSERT/DELETE/ISUPDATE demo';

-- Peek (does NOT consume)
SELECT METADATA$ACTION, METADATA$ISUPDATE, txn_id, txn_type, _source_file
FROM WM_MICRO.RAW.STRM_OMS_TRANSACTION_RT LIMIT 20;
SELECT SYSTEM$STREAM_HAS_DATA('WM_MICRO.RAW.STRM_OMS_TRANSACTION_RT');

/* ---------------------------------------------------------------------------------
   Stream-TRIGGERED task: no SCHEDULE. Snowflake runs it when the stream has data
   (minimum 30 s apart). Before triggered tasks existed the pattern was:
       SCHEDULE = '1 MINUTE'  WHEN SYSTEM$STREAM_HAS_DATA('...')
   The WHEN check is free - no warehouse starts if it is FALSE.
   --------------------------------------------------------------------------------- */
CREATE OR REPLACE TASK WM_MICRO.RT.TSK_MERGE_INTRADAY_TRADE
  WAREHOUSE = WM_LOAD_WH
  COMMENT = 'Triggered by new rows in RAW.OMS_TRANSACTION'
  WHEN SYSTEM$STREAM_HAS_DATA('WM_MICRO.RAW.STRM_OMS_TRANSACTION_RT')
AS
MERGE INTO WM_MICRO.RT.INTRADAY_TRADE t
USING (
    SELECT
        TRY_TO_NUMBER(txn_id)                         AS txn_id,
        TRY_TO_NUMBER(account_id)                     AS account_id,
        UPPER(TRIM(txn_type))                         AS txn_type,
        NULLIF(UPPER(TRIM(ticker)), '')               AS ticker,
        TRY_TO_NUMBER(quantity, 18, 4)                AS quantity,
        CASE UPPER(TRIM(txn_type))
             WHEN 'BUY'  THEN  TRY_TO_NUMBER(quantity, 18, 4)
             WHEN 'SELL' THEN -TRY_TO_NUMBER(quantity, 18, 4)
             ELSE 0 END                               AS signed_quantity,
        TRY_TO_NUMBER(price, 18, 4)                   AS price,
        TRY_TO_NUMBER(amount, 18, 2)                  AS amount,
        TRY_TO_NUMBER(fees, 18, 2)                    AS fees,
        UPPER(TRIM(channel))                          AS channel,
        TRY_TO_TIMESTAMP_NTZ(txn_ts)                  AS txn_ts,
        _source_file,
        _loaded_at
    FROM WM_MICRO.RAW.STRM_OMS_TRANSACTION_RT
    WHERE TRY_TO_NUMBER(txn_id) IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY txn_id ORDER BY _loaded_at DESC, _file_row_number DESC) = 1
) s
ON t.txn_id = s.txn_id
WHEN MATCHED THEN UPDATE SET
    account_id = s.account_id, txn_type = s.txn_type, ticker = s.ticker, quantity = s.quantity,
    signed_quantity = s.signed_quantity, price = s.price, amount = s.amount, fees = s.fees,
    channel = s.channel, txn_ts = s.txn_ts, _source_file = s._source_file,
    _updated_at = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
WHEN NOT MATCHED THEN INSERT
    (txn_id, account_id, txn_type, ticker, quantity, signed_quantity, price, amount, fees, channel,
     txn_ts, _source_file, _ingested_at, _updated_at)
VALUES
    (s.txn_id, s.account_id, s.txn_type, s.ticker, s.quantity, s.signed_quantity, s.price, s.amount,
     s.fees, s.channel, s.txn_ts, s._source_file, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ);

ALTER TASK WM_MICRO.RT.TSK_MERGE_INTRADAY_TRADE RESUME;
-- Run it right now instead of waiting for the trigger:
EXECUTE TASK WM_MICRO.RT.TSK_MERGE_INTRADAY_TRADE;

-- After ~30-60 s
SELECT COUNT(*) FROM WM_MICRO.RT.INTRADAY_TRADE;                      -- duplicates removed
SELECT SYSTEM$STREAM_HAS_DATA('WM_MICRO.RAW.STRM_OMS_TRANSACTION_RT'); -- FALSE: consumed
SHOW STREAMS IN DATABASE WM_MICRO;                                     -- see "stale", "stale_after"

/* Later, after loading batch_2 (EXECUTE TASK UTIL.TSK_EOD_ROOT), the stream fills again and
   this task fires on its own. To stop it:  ALTER TASK WM_MICRO.RT.TSK_MERGE_INTRADAY_TRADE SUSPEND; */
