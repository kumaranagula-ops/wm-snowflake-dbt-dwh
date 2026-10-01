/* =====================================================================================
   01_rbac.sql                      run as: SECURITYADMIN / SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   Role-based access control. Snowflake privileges are granted to ROLES, roles to USERS.

       ACCOUNTADMIN
         ├── SECURITYADMIN ── USERADMIN          (manage roles/users/grants)
         └── SYSADMIN                            (owns warehouses, database, schemas)
               ├── WM_LOADER       write RAW, use stages         (ingestion jobs / Snowpipe)
               ├── WM_TRANSFORMER  read RAW, write CNTL, build dbt schemas (dbt user)
               ├── WM_ANALYST      read MARTS / SHARE only         (BI users)
               └── WM_PII_READER   sees unmasked PII (see labs/L09_governance_security.sql)

   Rule of thumb: always grant custom roles up to SYSADMIN so admins can manage what
   those roles create.

   Topics: role hierarchy, object privileges, FUTURE grants (database vs schema level)
   ===================================================================================== */

SET MY_USER = CURRENT_USER();          -- change if dbt uses a different user

USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS WM_LOADER      COMMENT = 'Loads files into RAW';
CREATE ROLE IF NOT EXISTS WM_TRANSFORMER COMMENT = 'dbt: reads RAW, writes STAGING..MARTS, logs to CNTL';
CREATE ROLE IF NOT EXISTS WM_ANALYST     COMMENT = 'Read-only on marts';
CREATE ROLE IF NOT EXISTS WM_PII_READER  COMMENT = 'Allowed to see unmasked client PII';

USE ROLE SECURITYADMIN;
GRANT ROLE WM_LOADER      TO ROLE SYSADMIN;
GRANT ROLE WM_TRANSFORMER TO ROLE SYSADMIN;
GRANT ROLE WM_ANALYST     TO ROLE SYSADMIN;
GRANT ROLE WM_PII_READER  TO ROLE SYSADMIN;

GRANT ROLE WM_LOADER, WM_TRANSFORMER, WM_ANALYST TO USER IDENTIFIER($MY_USER);

-- ---------------------------------------------------------------- warehouses
GRANT USAGE, OPERATE ON WAREHOUSE WM_LOAD_WH      TO ROLE WM_LOADER;
GRANT USAGE, OPERATE ON WAREHOUSE WM_TRANSFORM_WH TO ROLE WM_TRANSFORMER;
GRANT USAGE          ON WAREHOUSE WM_BI_WH        TO ROLE WM_ANALYST;

-- ---------------------------------------------------------------- database
GRANT USAGE ON DATABASE WM_MICRO TO ROLE WM_LOADER;
GRANT USAGE ON DATABASE WM_MICRO TO ROLE WM_ANALYST;
GRANT USAGE, CREATE SCHEMA ON DATABASE WM_MICRO TO ROLE WM_TRANSFORMER;   -- dbt creates its own schemas

-- ---------------------------------------------------------------- RAW
GRANT USAGE ON SCHEMA WM_MICRO.RAW TO ROLE WM_LOADER;
GRANT USAGE ON SCHEMA WM_MICRO.RAW TO ROLE WM_TRANSFORMER;
-- FUTURE grants: apply automatically to tables created later in this schema
GRANT SELECT, INSERT ON FUTURE TABLES  IN SCHEMA WM_MICRO.RAW TO ROLE WM_LOADER;
GRANT SELECT         ON FUTURE TABLES  IN SCHEMA WM_MICRO.RAW TO ROLE WM_TRANSFORMER;
GRANT SELECT         ON FUTURE STREAMS IN SCHEMA WM_MICRO.RAW TO ROLE WM_TRANSFORMER;

-- ---------------------------------------------------------------- UTIL (stages, formats, procs)
GRANT USAGE ON SCHEMA WM_MICRO.UTIL TO ROLE WM_LOADER;
GRANT USAGE ON SCHEMA WM_MICRO.UTIL TO ROLE WM_TRANSFORMER;
GRANT USAGE ON FUTURE FILE FORMATS IN SCHEMA WM_MICRO.UTIL TO ROLE WM_LOADER;
GRANT READ, WRITE ON FUTURE STAGES IN SCHEMA WM_MICRO.UTIL TO ROLE WM_LOADER;
GRANT USAGE ON FUTURE PROCEDURES  IN SCHEMA WM_MICRO.UTIL TO ROLE WM_LOADER;
GRANT USAGE ON FUTURE FUNCTIONS   IN SCHEMA WM_MICRO.UTIL TO ROLE WM_TRANSFORMER;

-- ---------------------------------------------------------------- CNTL
GRANT USAGE ON SCHEMA WM_MICRO.CNTL TO ROLE WM_LOADER;
GRANT USAGE ON SCHEMA WM_MICRO.CNTL TO ROLE WM_TRANSFORMER;
GRANT SELECT, INSERT, UPDATE ON FUTURE TABLES IN SCHEMA WM_MICRO.CNTL TO ROLE WM_LOADER;
GRANT SELECT, INSERT, UPDATE ON FUTURE TABLES IN SCHEMA WM_MICRO.CNTL TO ROLE WM_TRANSFORMER;

-- ---------------------------------------------------------------- RT + GOVERNANCE
GRANT USAGE ON SCHEMA WM_MICRO.RT TO ROLE WM_ANALYST;
GRANT SELECT ON FUTURE TABLES         IN SCHEMA WM_MICRO.RT TO ROLE WM_ANALYST;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA WM_MICRO.RT TO ROLE WM_ANALYST;
GRANT USAGE ON SCHEMA WM_MICRO.GOVERNANCE TO ROLE WM_TRANSFORMER;

-- ---------------------------------------------------------------- dbt-built schemas
-- dbt creates MARTS / DEV_MARTS etc. later, owned by WM_TRANSFORMER.
-- Database-level future grants cover schemas that DON'T have their own schema-level
-- future grants. (Schema-level future grants WIN over database-level ones, which is why
-- WM_ANALYST does NOT get RAW / CNTL tables from the two lines below.)
GRANT USAGE  ON FUTURE SCHEMAS IN DATABASE WM_MICRO TO ROLE WM_ANALYST;
GRANT SELECT ON FUTURE TABLES  IN DATABASE WM_MICRO TO ROLE WM_ANALYST;
GRANT SELECT ON FUTURE VIEWS   IN DATABASE WM_MICRO TO ROLE WM_ANALYST;
-- dbt ALSO re-applies grants on every build via the `grants:` config in dbt_project.yml

-- Check
SHOW GRANTS TO ROLE WM_TRANSFORMER;
SHOW FUTURE GRANTS IN SCHEMA WM_MICRO.RAW;
