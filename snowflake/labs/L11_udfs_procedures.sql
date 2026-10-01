/* =====================================================================================
   L11_udfs_procedures.sql                    role: SYSADMIN   edition: any   trial: yes
   Topics: SQL UDF, Python UDF, SQL UDTF (table function), secure UDF,
           Snowflake Scripting procedure, Python (Snowpark) procedure,
           caller vs owner rights, sequences
   ===================================================================================== */
USE ROLE SYSADMIN;
USE WAREHOUSE WM_TRANSFORM_WH;
USE SCHEMA WM_MICRO.UTIL;

-- 1. SQL scalar UDF: Indian financial year label (Apr-Mar)
CREATE OR REPLACE FUNCTION FN_FISCAL_YEAR_IN(d DATE)
RETURNS VARCHAR
AS
$$
    'FY' || IFF(MONTH(d) >= 4, YEAR(d), YEAR(d) - 1) || '-' ||
    RIGHT(IFF(MONTH(d) >= 4, YEAR(d) + 1, YEAR(d))::VARCHAR, 2)
$$;
SELECT FN_FISCAL_YEAR_IN('2026-10-01'::DATE);        -- FY2026-27

-- 2. Python UDF: validate an Indian PAN format
CREATE OR REPLACE FUNCTION FN_IS_VALID_PAN(pan STRING)
RETURNS BOOLEAN
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'is_valid'
AS
$$
import re
_pat = re.compile(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
def is_valid(pan):
    return bool(pan) and bool(_pat.match(pan.strip().upper()))
$$;
SELECT pan, FN_IS_VALID_PAN(pan) FROM WM_MICRO.RAW.CRM_CLIENT LIMIT 10;

-- 3. SQL UDTF: returns a table - business days between two dates
CREATE OR REPLACE FUNCTION FN_BUSINESS_DAYS(start_d DATE, end_d DATE)
RETURNS TABLE (business_day DATE)
AS
$$
    SELECT d FROM (
        SELECT DATEADD('day', SEQ4(), start_d) AS d
        FROM TABLE(GENERATOR(ROWCOUNT => 3660))
    )
    WHERE d <= end_d AND DAYOFWEEKISO(d) <= 5
$$;
SELECT * FROM TABLE(FN_BUSINESS_DAYS('2026-09-25'::DATE, '2026-10-06'::DATE));

-- 4. Secure UDF: body hidden from non-owners (required for sharing UDFs)
CREATE OR REPLACE SECURE FUNCTION FN_MASK_EMAIL(e STRING) RETURNS STRING
AS $$ REGEXP_REPLACE(e, '^[^@]+', '*****') $$;

-- 5. Snowflake Scripting procedure: purge old load-audit rows, return how many
CREATE OR REPLACE PROCEDURE SP_PURGE_AUDIT(P_KEEP_DAYS NUMBER)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER                     -- runs with the CALLER's privileges (vs OWNER in SP_LOAD_SOURCE)
AS
$$
DECLARE
    n INTEGER;
BEGIN
    DELETE FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT
     WHERE audited_at < DATEADD('day', -1 * :P_KEEP_DAYS, CURRENT_TIMESTAMP());
    n := SQLROWCOUNT;                 -- rows affected by the last DML
    RETURN 'deleted ' || n || ' audit rows';
END;
$$;
CALL SP_PURGE_AUDIT(365);

-- 6. Python (Snowpark) procedure: row counts of every RAW table into a dict
--    (first use of Anaconda packages may require ORGADMIN to accept the Anaconda terms in Snowsight)
CREATE OR REPLACE PROCEDURE SP_RAW_ROW_COUNTS()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
def run(session):
    tables = session.sql(
        "SELECT table_name FROM WM_MICRO.INFORMATION_SCHEMA.TABLES "
        "WHERE table_schema = 'RAW' AND table_type = 'BASE TABLE'").collect()
    return {t["TABLE_NAME"]: session.table(f"WM_MICRO.RAW.{t['TABLE_NAME']}").count() for t in tables}
$$;
CALL SP_RAW_ROW_COUNTS();

-- 7. Sequences vs IDENTITY/AUTOINCREMENT (CNTL_FILE_LOAD_AUDIT uses AUTOINCREMENT)
CREATE OR REPLACE SEQUENCE SEQ_DEMO START = 1 INCREMENT = 1;
SELECT SEQ_DEMO.NEXTVAL, SEQ_DEMO.NEXTVAL;
-- Sequences guarantee uniqueness, NOT gap-free ordering. The dbt marts use hash surrogate
-- keys (MD5 of the business key) instead: deterministic, rebuildable, parallel-safe.

/* UDF / proc rules of thumb
   * Function = returns a value, used inside SQL, no DDL/DML side effects.
   * Procedure = CALLed, can run DDL/DML, dynamic SQL, loops, transactions.
   * Languages: SQL, JavaScript, Python, Java, Scala. External functions call an API (AWS API GW). */
