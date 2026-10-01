/* =====================================================================================
   L09_governance_security.sql     role: SYSADMIN / ACCOUNTADMIN
   edition: masking, row access, tag-based masking = ENTERPRISE+ ; tags = Standard+
   trial: yes if your trial is Enterprise (Snowflake trials let you pick)
   Prereq: dbt build (dev) -> DEV_MARTS.DIM_CLIENT
   Topics: object tags, dynamic data masking, tag-based masking, row access policies,
           mapping tables, how to keep policies on dbt-rebuilt tables, network policy,
           ACCESS_HISTORY, data classification
   ===================================================================================== */
USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.GOVERNANCE;

-- 1. Tag: metadata label with allowed values
CREATE TAG IF NOT EXISTS PII_TYPE ALLOWED_VALUES 'EMAIL', 'PHONE', 'PAN', 'DOB', 'NAME'
  COMMENT = 'Classifies personal data columns';

-- 2. Masking policies (one per data type). Role check uses IS_ROLE_IN_SESSION so role
--    hierarchy and secondary roles are respected.
CREATE OR REPLACE MASKING POLICY MP_PII_STRING AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('WM_PII_READER') THEN val
        WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('WM_MICRO.GOVERNANCE.PII_TYPE') = 'EMAIL'
             THEN REGEXP_REPLACE(val, '^[^@]+', '*****')                      -- *****@mail.in
        WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('WM_MICRO.GOVERNANCE.PII_TYPE') = 'PAN'
             THEN 'XXXXX' || RIGHT(val, 5)
        ELSE '***MASKED***'
    END;

CREATE OR REPLACE MASKING POLICY MP_PII_DATE AS (val DATE) RETURNS DATE ->
    CASE WHEN IS_ROLE_IN_SESSION('WM_PII_READER') THEN val
         ELSE DATE_FROM_PARTS(YEAR(val), 1, 1) END;                           -- keep year only

-- 3. Tag-based masking: attach policies to the TAG -> every column with that tag is masked
USE ROLE ACCOUNTADMIN;
GRANT APPLY TAG ON ACCOUNT TO ROLE WM_TRANSFORMER;                 -- dbt post-hook sets tags
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE WM_TRANSFORMER;
GRANT USAGE ON SCHEMA WM_MICRO.GOVERNANCE TO ROLE WM_TRANSFORMER;
ALTER TAG WM_MICRO.GOVERNANCE.PII_TYPE SET
    MASKING POLICY WM_MICRO.GOVERNANCE.MP_PII_STRING,
    MASKING POLICY WM_MICRO.GOVERNANCE.MP_PII_DATE;
USE ROLE SYSADMIN;

-- 4. Row access policy: an advisor role only sees its own clients
CREATE TABLE IF NOT EXISTS ADVISOR_ROLE_MAP (role_name VARCHAR, advisor_id NUMBER);
INSERT INTO ADVISOR_ROLE_MAP
SELECT 'WM_ADVISOR_201', 201 WHERE NOT EXISTS (SELECT 1 FROM ADVISOR_ROLE_MAP WHERE role_name = 'WM_ADVISOR_201');

CREATE OR REPLACE ROW ACCESS POLICY RAP_ADVISOR_CLIENTS AS (p_advisor_id NUMBER) RETURNS BOOLEAN ->
       IS_ROLE_IN_SESSION('SYSADMIN')
    OR IS_ROLE_IN_SESSION('WM_TRANSFORMER')     -- dbt must see everything to build facts
    OR IS_ROLE_IN_SESSION('WM_ANALYST')
    OR EXISTS (SELECT 1 FROM WM_MICRO.GOVERNANCE.ADVISOR_ROLE_MAP m
               WHERE m.role_name = CURRENT_ROLE() AND m.advisor_id = p_advisor_id);

/* 5. Applying policies to dbt tables.
      dbt does CREATE OR REPLACE on every run -> tags/policies on the old table are lost.
      So dbt re-applies them in a post-hook. Turn it on with:
          dbt build --vars '{enable_governance: true}'
      (macro: macros/apply_governance.sql, configured on dim_client)
      What the post-hook runs, for reference: */
-- ALTER TABLE WM_MICRO.DEV_MARTS.DIM_CLIENT MODIFY COLUMN email         SET TAG WM_MICRO.GOVERNANCE.PII_TYPE = 'EMAIL';
-- ALTER TABLE WM_MICRO.DEV_MARTS.DIM_CLIENT MODIFY COLUMN pan           SET TAG WM_MICRO.GOVERNANCE.PII_TYPE = 'PAN';
-- ALTER TABLE WM_MICRO.DEV_MARTS.DIM_CLIENT ADD ROW ACCESS POLICY WM_MICRO.GOVERNANCE.RAP_ADVISOR_CLIENTS ON (primary_advisor_id);

-- 6. Test it
SET MY_USER = CURRENT_USER();
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS WM_ADVISOR_201;
GRANT ROLE WM_ADVISOR_201 TO ROLE SYSADMIN;
GRANT ROLE WM_ADVISOR_201 TO USER IDENTIFIER($MY_USER);
GRANT USAGE ON WAREHOUSE WM_BI_WH TO ROLE WM_ADVISOR_201;
GRANT USAGE ON DATABASE WM_MICRO TO ROLE WM_ADVISOR_201;
GRANT USAGE ON SCHEMA WM_MICRO.DEV_MARTS TO ROLE WM_ADVISOR_201;
GRANT SELECT ON TABLE WM_MICRO.DEV_MARTS.DIM_CLIENT TO ROLE WM_ADVISOR_201;

USE ROLE WM_ADVISOR_201; USE WAREHOUSE WM_BI_WH;
SELECT client_id, client_name, email, pan, date_of_birth, primary_advisor_id
FROM WM_MICRO.DEV_MARTS.DIM_CLIENT;                    -- only advisor 201's clients, PII masked

USE ROLE WM_ANALYST;
SELECT client_id, email, pan FROM WM_MICRO.DEV_MARTS.DIM_CLIENT LIMIT 5;   -- all rows, masked

USE ROLE SYSADMIN;   -- SYSADMIN inherits WM_PII_READER -> unmasked
SELECT client_id, email, pan FROM WM_MICRO.DEV_MARTS.DIM_CLIENT LIMIT 5;

-- 7. Where are my policies / tags?
SELECT * FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME => 'WM_MICRO.DEV_MARTS.DIM_CLIENT', REF_ENTITY_DOMAIN => 'table'));
SELECT * FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('WM_MICRO.DEV_MARTS.DIM_CLIENT', 'table'));

/* 8. More governance features to know
   * Projection policy  - column can be filtered on but not SELECTed
   * Aggregation policy - only aggregated results with min group size
   * SYSTEM$CLASSIFY / automatic sensitive data classification - suggests PII tags
   * SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY (Enterprise) - who read which column
   * Network policies   - IP allow/deny lists:  CREATE NETWORK POLICY ... ALLOWED_IP_LIST = (...)
   * Authentication     - MFA, key-pair (used by dbt/CI here), OAuth, SSO/SAML
   * Encryption         - always on (AES-256), Tri-Secret Secure = customer key (BC)           */
