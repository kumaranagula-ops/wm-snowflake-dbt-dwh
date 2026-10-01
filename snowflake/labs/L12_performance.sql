/* =====================================================================================
   L12_performance.sql             role: SYSADMIN
   edition: clustering/caching = any; search optimization, materialized views,
            query acceleration, multi-cluster = ENTERPRISE+
   Prereq: dbt build (dev)
   Topics: micro-partitions & pruning, clustering keys, the 3 caches, warehouse sizing,
           search optimization, materialized views, query acceleration, query profile
   ===================================================================================== */
USE ROLE SYSADMIN;
USE WAREHOUSE WM_TRANSFORM_WH;
USE SCHEMA WM_MICRO.DEV_MARTS;

/* 1. Micro-partitions: Snowflake stores every table as immutable 50-500 MB (uncompressed)
      columnar files with min/max metadata per column. A WHERE on a column lets it skip
      (prune) partitions whose range can't match. Clustering = keeping similar values together
      so pruning works. dbt sets cluster_by on FACT_TRANSACTION (txn_date) and
      FACT_DAILY_POSITION (position_date). */
SELECT SYSTEM$CLUSTERING_INFORMATION('FACT_TRANSACTION', '(txn_date)');
SELECT SYSTEM$CLUSTERING_DEPTH('FACT_TRANSACTION', '(txn_date)');
-- Automatic Clustering runs in the background (serverless credits):
-- ALTER TABLE FACT_TRANSACTION SUSPEND RECLUSTER;  /  RESUME RECLUSTER;
-- Tiny tables like ours have 1 partition, so numbers are trivial - the commands are the point.

-- 2. Pruning in the query profile: run, then open Query Profile > "Partitions scanned / total"
SELECT SUM(net_cash_flow) FROM FACT_TRANSACTION WHERE txn_date = '2026-09-01';

-- 3. The three caches
--    a) Result cache (24h, cloud services, free): identical query + unchanged data -> instant
SELECT COUNT(*), SUM(gross_amount) FROM FACT_TRANSACTION;
SELECT COUNT(*), SUM(gross_amount) FROM FACT_TRANSACTION;        -- profile shows "QUERY RESULT REUSE"
ALTER SESSION SET USE_CACHED_RESULT = FALSE;                      -- for honest benchmarking
--    b) Warehouse (local SSD) cache: data read stays on the warehouse until it suspends
--    c) Metadata cache: COUNT(*), MIN/MAX on a table answered without a warehouse
SELECT MIN(txn_date), MAX(txn_date) FROM FACT_TRANSACTION;
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- 4. Warehouse sizing: scale UP (size) for big/complex queries, OUT (clusters) for concurrency
-- ALTER WAREHOUSE WM_TRANSFORM_WH SET WAREHOUSE_SIZE = 'SMALL';   -- each size doubles credits/hour
-- Enterprise: ALTER WAREHOUSE WM_BI_WH SET MAX_CLUSTER_COUNT = 3 SCALING_POLICY = 'ECONOMY';

-- 5. ENTERPRISE: Search Optimization - point lookups / selective filters on high-cardinality columns
-- ALTER TABLE FACT_TRANSACTION ADD SEARCH OPTIMIZATION ON EQUALITY(txn_id, account_key);
-- SELECT * FROM FACT_TRANSACTION WHERE txn_id = 900123;
-- SHOW TABLES LIKE 'FACT_TRANSACTION';  -- search_optimization_progress
-- (dbt would drop it on full rebuild; incremental models keep the table, so it survives)

-- 6. ENTERPRISE: Materialized view - single table, no joins, auto-maintained, always fresh
-- CREATE OR REPLACE MATERIALIZED VIEW WM_MICRO.SCRATCH.MV_DAILY_FLOW AS
-- SELECT txn_date, txn_type_code, SUM(net_cash_flow) AS net_flow, COUNT(*) AS txns
-- FROM WM_MICRO.DEV_MARTS.FACT_TRANSACTION GROUP BY txn_date, txn_type_code;
-- The optimizer can rewrite queries on the base table to use the MV automatically.

-- 7. ENTERPRISE: Query Acceleration Service - offloads scan-heavy parts to serverless compute
-- ALTER WAREHOUSE WM_BI_WH SET ENABLE_QUERY_ACCELERATION = TRUE QUERY_ACCELERATION_MAX_SCALE_FACTOR = 4;
-- SELECT SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>');

-- 8. Find slow / expensive queries
SELECT query_id, LEFT(query_text, 80) AS sql, warehouse_name, total_elapsed_time / 1000 AS secs,
       partitions_scanned, partitions_total, bytes_spilled_to_local_storage, bytes_spilled_to_remote_storage
FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 200))
WHERE warehouse_name IS NOT NULL
ORDER BY total_elapsed_time DESC LIMIT 20;
-- Spilling to remote storage = warehouse too small for that query.

/* Checklist when a query is slow: pruning (partitions scanned), spilling, exploding joins
   (rows out >> rows in), queueing (warehouse overloaded -> multi-cluster), remote I/O,
   non-sargable filters (functions on the filtered column: WHERE TO_CHAR(txn_date) = ...). */
