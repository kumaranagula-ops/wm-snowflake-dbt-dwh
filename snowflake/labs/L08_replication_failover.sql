/* =====================================================================================
   L08_replication_failover.sql    role: ORGADMIN + ACCOUNTADMIN
   edition: replication groups = Standard+, FAILOVER groups & client redirect = Business Critical
   trial: TEMPLATE - needs two accounts in the same organization (e.g. Mumbai + Singapore region).
   Topics: database/account object replication, replication vs failover groups, refresh
           schedule, promoting a secondary, client redirect, replication cost
   ===================================================================================== */

/* Why: DR (region/cloud outage), moving data closer to users, sharing across regions.
   Replication copies DATA + OBJECTS to a secondary account; the secondary is read-only
   until it is promoted (failover).

     Replication group  -> read-only secondary copy, refreshed on a schedule
     Failover group     -> same, plus the secondary can be PROMOTED to primary (BC edition)
     Object types       -> DATABASES, SHARES, USERS, ROLES, WAREHOUSES, INTEGRATIONS,
                           NETWORK POLICIES, RESOURCE MONITORS, ACCOUNT PARAMETERS ...      */

-- 0. ORGADMIN enables replication on both accounts
USE ROLE ORGADMIN;
SHOW ACCOUNTS;   -- note organization_name, account_name of primary (PRIMARY_ACCT) and DR (DR_ACCT)
-- SELECT SYSTEM$GLOBAL_ACCOUNT_SET_PARAMETER('<org>.<PRIMARY_ACCT>', 'ENABLE_ACCOUNT_DATABASE_REPLICATION', 'true');
-- SELECT SYSTEM$GLOBAL_ACCOUNT_SET_PARAMETER('<org>.<DR_ACCT>',      'ENABLE_ACCOUNT_DATABASE_REPLICATION', 'true');

-- 1. PRIMARY account
USE ROLE ACCOUNTADMIN;
CREATE REPLICATION GROUP IF NOT EXISTS WM_RG
  OBJECT_TYPES = DATABASES, SHARES
  ALLOWED_DATABASES = WM_MICRO
  ALLOWED_SHARES = WM_CLIENT_AUM_SHARE
  ALLOWED_ACCOUNTS = <org>.<DR_ACCT>
  REPLICATION_SCHEDULE = '60 MINUTE';

-- Business Critical: a failover group instead (can include account objects)
-- CREATE FAILOVER GROUP WM_FG
--   OBJECT_TYPES = DATABASES, ROLES, USERS, WAREHOUSES, RESOURCE MONITORS
--   ALLOWED_DATABASES = WM_MICRO
--   ALLOWED_ACCOUNTS = <org>.<DR_ACCT>
--   REPLICATION_SCHEDULE = '10 MINUTE';

-- 2. SECONDARY (DR) account
-- USE ROLE ACCOUNTADMIN;
-- CREATE REPLICATION GROUP WM_RG AS REPLICA OF <org>.<PRIMARY_ACCT>.WM_RG;
-- ALTER REPLICATION GROUP WM_RG REFRESH;                 -- first full sync (or wait for schedule)
-- SHOW DATABASES;                                        -- WM_MICRO is_current / read-only

-- 3. Monitor
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.REPLICATION_GROUP_REFRESH_PROGRESS('WM_RG'));
-- SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_USAGE_HISTORY;   -- credits + bytes transferred

-- 4. Failover (Business Critical) - run in the DR account during an outage
-- ALTER FAILOVER GROUP WM_FG PRIMARY;

-- 5. Client redirect: apps connect to a CONNECTION URL that you repoint during failover
-- CREATE CONNECTION WM_CONN;                                                 (primary)
-- ALTER CONNECTION WM_CONN ENABLE FAILOVER TO ACCOUNTS <org>.<DR_ACCT>;
-- CREATE CONNECTION WM_CONN AS REPLICA OF <org>.<PRIMARY_ACCT>.WM_CONN;      (DR)
-- ALTER CONNECTION WM_CONN PRIMARY;                                          (DR, at failover)
-- Users connect to <org>-wm_conn.snowflakecomputing.com

/* Things that do NOT replicate or need care: internal stage FILES, pipes on internal
   stages, external tables need their integration replicated, tasks replicate but stay
   suspended on the secondary, temporary tables never replicate.
   Cost = data transfer (cross-region/cloud) + compute for refresh + storage in DR. */
