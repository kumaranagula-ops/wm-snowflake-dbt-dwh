/* =====================================================================================
   08_dynamic_tables.sql                      run as: SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   DYNAMIC TABLE = "a table defined by a query that Snowflake keeps up to date".
   You declare WHAT (the SELECT) and HOW FRESH (TARGET_LAG); Snowflake decides WHEN and
   refreshes incrementally where it can. It replaces a lot of stream + task + MERGE code.

       RT.INTRADAY_TRADE ─► DT_INTRADAY_POSITION (lag DOWNSTREAM) ─┐
       RAW.MKT_PRICE     ─► DT_LATEST_PRICE      (lag DOWNSTREAM) ─┼─► DT_CLIENT_EXPOSURE (lag 1 hour)
       RAW.CORE_ACCOUNT_HOLDER ────────────────────────────────────┘

   TARGET_LAG = DOWNSTREAM  -> refresh only when a downstream DT needs it
   REFRESH_MODE = INCREMENTAL | FULL | AUTO (Snowflake chooses; check SHOW DYNAMIC TABLES)

   Streams+Tasks vs Dynamic Tables vs Materialized Views
     Streams+Tasks   imperative, full control (MERGE logic, SCD, side effects, procs)
     Dynamic tables  declarative SELECT, joins/aggregations allowed, lag-based, chainable
     Materialized views (Enterprise) single table only, no joins, always current, auto-maintained
   ===================================================================================== */

USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.RT;

CREATE OR REPLACE DYNAMIC TABLE DT_INTRADAY_POSITION
  TARGET_LAG   = DOWNSTREAM
  WAREHOUSE    = WM_TRANSFORM_WH
  REFRESH_MODE = AUTO          -- set INCREMENTAL to force it; creation fails if the query can't be incremental
  INITIALIZE   = ON_CREATE
  COMMENT = 'Net quantity per account x ticker from the intraday feed'
AS
SELECT account_id,
       ticker,
       SUM(signed_quantity) AS quantity_held,
       COUNT(*)             AS trade_count,
       MAX(txn_ts)          AS last_trade_ts
FROM WM_MICRO.RT.INTRADAY_TRADE
WHERE txn_type IN ('BUY', 'SELL')
GROUP BY account_id, ticker;

CREATE OR REPLACE DYNAMIC TABLE DT_LATEST_PRICE
  TARGET_LAG   = DOWNSTREAM
  WAREHOUSE    = WM_TRANSFORM_WH
  REFRESH_MODE = AUTO
  COMMENT = 'Most recent close per ticker'
AS
SELECT UPPER(TRIM(ticker))                AS ticker,
       TRY_TO_DATE(price_date)            AS price_date,
       TRY_TO_NUMBER(close, 18, 4)        AS close_price
FROM WM_MICRO.RAW.MKT_PRICE
QUALIFY ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(ticker)) ORDER BY TRY_TO_DATE(price_date) DESC, _loaded_at DESC) = 1;

CREATE OR REPLACE DYNAMIC TABLE DT_CLIENT_EXPOSURE
  TARGET_LAG   = '1 hour'
  WAREHOUSE    = WM_TRANSFORM_WH
  REFRESH_MODE = AUTO
  COMMENT = 'Intraday market value per client (ownership-weighted for joint accounts)'
AS
WITH holder AS (
    SELECT TRY_TO_NUMBER(account_id)              AS account_id,
           TRY_TO_NUMBER(client_id)               AS client_id,
           TRY_TO_NUMBER(ownership_pct, 5, 2) / 100 AS ownership_share
    FROM WM_MICRO.RAW.CORE_ACCOUNT_HOLDER
    QUALIFY ROW_NUMBER() OVER (PARTITION BY account_id, client_id ORDER BY _loaded_at DESC) = 1
)
SELECT h.client_id,
       COUNT(DISTINCT p.account_id)                                       AS accounts,
       COUNT(DISTINCT p.ticker)                                           AS securities,
       ROUND(SUM(p.quantity_held * lp.close_price * h.ownership_share), 2) AS market_value_inr,
       MAX(p.last_trade_ts)                                               AS last_trade_ts
FROM DT_INTRADAY_POSITION p
JOIN DT_LATEST_PRICE lp ON lp.ticker = p.ticker
JOIN holder h           ON h.account_id = p.account_id
WHERE p.quantity_held <> 0
GROUP BY h.client_id;

-- Inspect -------------------------------------------------------------------------
SHOW DYNAMIC TABLES IN SCHEMA WM_MICRO.RT;           -- refresh_mode, target_lag, scheduling_state

SELECT name, state, refresh_action, refresh_trigger, refresh_start_time, refresh_end_time
FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
ORDER BY refresh_start_time DESC LIMIT 20;

SELECT * FROM DT_CLIENT_EXPOSURE ORDER BY market_value_inr DESC;

-- Manual refresh / pause (keeps a trial account cheap) -------------------------------
ALTER DYNAMIC TABLE DT_CLIENT_EXPOSURE REFRESH;
-- ALTER DYNAMIC TABLE DT_CLIENT_EXPOSURE SUSPEND;
-- ALTER DYNAMIC TABLE DT_CLIENT_EXPOSURE RESUME;

/* dbt can also own dynamic tables:
     {{ config(materialized='dynamic_table', snowflake_warehouse='WM_TRANSFORM_WH', target_lag='1 hour') }}
   They are kept native here so the whole real-time path is visible in one place. */
