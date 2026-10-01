/* =====================================================================================
   05_load_framework.sql                      run as: SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   Metadata-driven bulk loading with COPY INTO.

   UTIL.SP_LOAD_SOURCE('<system>', '<batch_id>')
     for each active row in CNTL_SOURCE_CONFIG for that system:
       1. builds the column list + "$1, $2, ..." from INFORMATION_SCHEMA.COLUMNS
       2. runs COPY INTO RAW.<table> FROM (SELECT $1.., METADATA$FILENAME, ...) @stage/path
       3. writes one CNTL_FILE_LOAD_AUDIT row per file from COPY_HISTORY
     on any error: logs PROC_ERROR to the audit table and re-raises (so the task fails)

   COPY INTO facts worth knowing for interviews
   * Load metadata: Snowflake remembers which files were loaded into a table for 64 days.
     Re-running COPY skips them -> COPY is idempotent. FORCE = TRUE reloads anyway.
   * ON_ERROR: ABORT_STATEMENT (default for COPY) | CONTINUE | SKIP_FILE | SKIP_FILE_<n> | SKIP_FILE_<n>%
     (Snowpipe default is SKIP_FILE)
   * Transformations allowed in COPY: column reorder/omit, casts, METADATA$ columns, simple
     functions. Not allowed: joins, GROUP BY, filters (WHERE).
   * Recommended file size: ~100-250 MB compressed for parallelism.
   ===================================================================================== */

USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.UTIL;

CREATE OR REPLACE PROCEDURE SP_LOAD_SOURCE(P_SOURCE_SYSTEM VARCHAR, P_BATCH_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
COMMENT = 'COPY INTO every active feed of a source system, audit each file into CNTL_FILE_LOAD_AUDIT'
AS
$$
DECLARE
    v_start    TIMESTAMP_LTZ;
    v_source   VARCHAR;
    v_target   VARCHAR;
    v_fqn      VARCHAR;
    v_schema   VARCHAR;
    v_table    VARCHAR;
    v_path     VARCHAR;
    v_ff       VARCHAR;
    v_pattern  VARCHAR;
    v_on_error VARCHAR;
    v_cols     VARCHAR;
    v_sel      VARCHAR;
    v_sql      VARCHAR;
    v_err      VARCHAR;
    v_feeds    INTEGER DEFAULT 0;
    v_files    INTEGER DEFAULT 0;
    v_rows     INTEGER DEFAULT 0;
    rs         RESULTSET;
BEGIN
    rs := (SELECT source_name, target_table, stage_path, file_format, file_pattern, on_error
             FROM WM_MICRO.CNTL.CNTL_SOURCE_CONFIG
            WHERE source_system = :P_SOURCE_SYSTEM AND is_active
            ORDER BY load_order);
    LET c1 CURSOR FOR rs;

    FOR rec IN c1 DO
        v_start    := CURRENT_TIMESTAMP();
        v_source   := rec.source_name;
        v_target   := rec.target_table;
        v_fqn      := 'WM_MICRO.' || rec.target_table;
        v_schema   := SPLIT_PART(rec.target_table, '.', 1);
        v_table    := SPLIT_PART(rec.target_table, '.', 2);
        v_path     := rec.stage_path;
        v_ff       := rec.file_format;
        v_pattern  := rec.file_pattern;
        v_on_error := rec.on_error;

        -- business columns = every column not starting with "_" , in table order
        SELECT LISTAGG(column_name, ', ')              WITHIN GROUP (ORDER BY ordinal_position),
               LISTAGG('$' || ordinal_position, ', ') WITHIN GROUP (ORDER BY ordinal_position)
          INTO :v_cols, :v_sel
          FROM WM_MICRO.INFORMATION_SCHEMA.COLUMNS
         WHERE table_schema = :v_schema
           AND table_name   = :v_table
           AND LEFT(column_name, 1) <> '_';

        v_sql := 'COPY INTO ' || v_fqn ||
                 ' (' || v_cols || ', _SOURCE_FILE, _FILE_ROW_NUMBER, _FILE_LAST_MODIFIED, _BATCH_ID)' ||
                 ' FROM (SELECT ' || v_sel || ', METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,' ||
                 ' METADATA$FILE_LAST_MODIFIED, ''' || P_BATCH_ID || '''' ||
                 ' FROM @WM_MICRO.UTIL.STG_LANDING/' || v_path || ')' ||
                 ' FILE_FORMAT = (FORMAT_NAME = ''WM_MICRO.UTIL.' || v_ff || ''')' ||
                 ' PATTERN = ''' || v_pattern || '''' ||
                 ' ON_ERROR = ''' || v_on_error || '''';

        EXECUTE IMMEDIATE :v_sql;

        INSERT INTO WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT
              (batch_id, source_system, source_name, target_table, file_name, status,
               rows_parsed, rows_loaded, error_count, first_error, last_load_time)
        SELECT :P_BATCH_ID, :P_SOURCE_SYSTEM, :v_source, :v_target, file_name, status,
               row_parsed, row_count, error_count, first_error_message, last_load_time
          FROM TABLE(WM_MICRO.INFORMATION_SCHEMA.COPY_HISTORY(
                    TABLE_NAME => :v_fqn, START_TIME => :v_start));

        v_feeds := v_feeds + 1;
    END FOR;

    SELECT COUNT(*), COALESCE(SUM(rows_loaded), 0) INTO :v_files, :v_rows
      FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT
     WHERE batch_id = :P_BATCH_ID AND source_system = :P_SOURCE_SYSTEM;

    RETURN P_SOURCE_SYSTEM || ': ' || v_feeds || ' feeds, ' || v_files || ' files, ' || v_rows || ' rows';

EXCEPTION
    WHEN OTHER THEN
        v_err := SQLERRM;
        INSERT INTO WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT
              (batch_id, source_system, source_name, target_table, status, first_error)
        VALUES (:P_BATCH_ID, :P_SOURCE_SYSTEM, COALESCE(:v_source, '?'), COALESCE(:v_target, '?'), 'PROC_ERROR', :v_err);
        RAISE;
END;
$$;

/* ---------------------------------------------------------------------------------
   Manual run (the EOD task graph in 06 does exactly this on a schedule).
   Upload files first:  ./scripts/upload_batch.sh batch_1
   --------------------------------------------------------------------------------- */
USE WAREHOUSE WM_LOAD_WH;
SET BATCH_ID = 'MANUAL_' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

INSERT INTO WM_MICRO.CNTL.CNTL_BATCH_RUN (batch_id, pipeline_name, target_name, invoked_by, status, started_at)
SELECT $BATCH_ID, 'MANUAL_INGEST', 'SNOWFLAKE', CURRENT_USER(), 'RUNNING', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;

CALL SP_LOAD_SOURCE('CRM',  $BATCH_ID);
CALL SP_LOAD_SOURCE('CORE', $BATCH_ID);
CALL SP_LOAD_SOURCE('MKT',  $BATCH_ID);
CALL SP_LOAD_SOURCE('OMS',  $BATCH_ID);

UPDATE WM_MICRO.CNTL.CNTL_BATCH_RUN
   SET status = 'SUCCEEDED', ended_at = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
       files_loaded = (SELECT COUNT(*)         FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT WHERE batch_id = $BATCH_ID),
       rows_loaded  = (SELECT SUM(rows_loaded) FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT WHERE batch_id = $BATCH_ID)
 WHERE batch_id = $BATCH_ID;

-- What happened?
SELECT source_system, source_name, file_name, status, rows_parsed, rows_loaded, error_count, first_error
FROM WM_MICRO.CNTL.CNTL_FILE_LOAD_AUDIT WHERE batch_id = $BATCH_ID ORDER BY audit_id;

-- Run the same CALLs again: 0 files - COPY load metadata skips files already loaded.
