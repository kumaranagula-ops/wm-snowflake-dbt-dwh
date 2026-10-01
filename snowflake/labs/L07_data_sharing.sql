/* =====================================================================================
   L07_data_sharing.sql            role: ACCOUNTADMIN   edition: any
   trial: partly - creating the share works; adding a consumer needs a 2nd account
          (trial accounts may not be allowed to create reader accounts).
   Prereq: dbt build with prod target (schema SHARE) - or change SHARE -> DEV_SHARE below.
   Topics: secure data sharing (no copy, no ETL), shares, secure views, database roles,
           reader (managed) accounts, consumer side, multi-tenant pattern, listings
   ===================================================================================== */

/* How it works: the provider grants read access on objects to a SHARE; the consumer
   creates a read-only DATABASE FROM SHARE. No data is copied - consumers query the
   provider's micro-partitions using THEIR OWN warehouse (the provider pays storage only).
   Only SECURE views / secure UDFs (or tables) can be shared - secure hides the definition. */

USE ROLE ACCOUNTADMIN;
SET SHARE_SCHEMA = 'WM_MICRO.SHARE';         -- dbt prod target builds SHARE.SHARE_CLIENT_AUM_MONTHLY

-- 1. Provider: create the share and grant objects to it
CREATE SHARE IF NOT EXISTS WM_CLIENT_AUM_SHARE COMMENT = 'Monthly client AUM for the group risk team';
GRANT USAGE ON DATABASE WM_MICRO                                    TO SHARE WM_CLIENT_AUM_SHARE;
GRANT USAGE ON SCHEMA   IDENTIFIER($SHARE_SCHEMA)                   TO SHARE WM_CLIENT_AUM_SHARE;
GRANT SELECT ON VIEW    WM_MICRO.SHARE.SHARE_CLIENT_AUM_MONTHLY     TO SHARE WM_CLIENT_AUM_SHARE;
SHOW GRANTS TO SHARE WM_CLIENT_AUM_SHARE;

-- 2. Add consumer account(s) in the same region (cross-region needs replication / listings)
-- ALTER SHARE WM_CLIENT_AUM_SHARE ADD ACCOUNTS = <ORG_NAME>.<CONSUMER_ACCOUNT_NAME>;
SHOW SHARES LIKE 'WM_%';

-- 3. Consumer without a Snowflake account -> READER account (provider pays its compute)
-- CREATE MANAGED ACCOUNT WM_READER
--   ADMIN_NAME = 'wm_reader_admin', ADMIN_PASSWORD = '<Strong-Passw0rd!>', TYPE = READER;
-- SHOW MANAGED ACCOUNTS;   -- gives the reader account locator, then:
-- ALTER SHARE WM_CLIENT_AUM_SHARE ADD ACCOUNTS = <reader_account_locator>;

-- 4. Consumer side (run in the consumer account)
-- CREATE DATABASE WM_SHARED FROM SHARE <PROVIDER_ORG>.<PROVIDER_ACCOUNT>.WM_CLIENT_AUM_SHARE;
-- GRANT IMPORTED PRIVILEGES ON DATABASE WM_SHARED TO ROLE ANALYST;
-- SELECT * FROM WM_SHARED.SHARE.SHARE_CLIENT_AUM_MONTHLY;

-- 5. Database roles: package several objects under one role inside the share
USE ROLE SYSADMIN;
CREATE DATABASE ROLE IF NOT EXISTS WM_MICRO.DR_SHARE_READER;
GRANT USAGE  ON SCHEMA WM_MICRO.SHARE                          TO DATABASE ROLE WM_MICRO.DR_SHARE_READER;
GRANT SELECT ON VIEW   WM_MICRO.SHARE.SHARE_CLIENT_AUM_MONTHLY TO DATABASE ROLE WM_MICRO.DR_SHARE_READER;
USE ROLE ACCOUNTADMIN;
GRANT DATABASE ROLE WM_MICRO.DR_SHARE_READER TO SHARE WM_CLIENT_AUM_SHARE;
-- Consumer: GRANT DATABASE ROLE WM_SHARED.DR_SHARE_READER TO ROLE ANALYST;

/* 6. Multi-tenant pattern: ONE share, many consumers, each sees only its rows.
      Secure view filters on CURRENT_ACCOUNT() via an entitlement table:

      CREATE SECURE VIEW SHARE.V_AUM_BY_TENANT AS
      SELECT a.* FROM MARTS.FACT_CLIENT_AUM_MONTHLY a
      JOIN CNTL.SHARE_ENTITLEMENT e
        ON e.branch_region = a.region AND e.consumer_account = CURRENT_ACCOUNT();

   7. Snowflake Marketplace / private LISTINGS wrap a share with a description, usage
      examples and cross-region auto-fulfilment (Provider Studio in Snowsight).        */

-- Cleanup
-- DROP SHARE WM_CLIENT_AUM_SHARE;
