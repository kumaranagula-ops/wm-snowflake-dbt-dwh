/* =====================================================================================
   02_control_tables.sql                      run as: SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   CNTL_* tables are the "operational memory" of the warehouse. Nothing in a report reads
   them; operations / support teams do.

     CNTL_SOURCE_CONFIG    what to load: one row per source feed (metadata-driven loading)
     CNTL_BATCH_RUN        one row per pipeline run (Snowflake EOD task graph AND each dbt invocation)
     CNTL_FILE_LOAD_AUDIT  one row per file loaded by COPY INTO (rows parsed/loaded/errors)
     CNTL_WATERMARK        high-water mark per incremental object (last _LOADED_AT processed)
     CNTL_DQ_RESULT        one row per dbt test per run (pass / warn / fail + failing rows)

   Note: PRIMARY KEY / FOREIGN KEY / UNIQUE constraints in Snowflake are INFORMATIONAL only
   (not enforced; only NOT NULL is enforced). We still declare them: BI tools and ER
   diagram tools read them, and they document intent.
   ===================================================================================== */

USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.CNTL;

CREATE TABLE IF NOT EXISTS CNTL_SOURCE_CONFIG (
    source_system   VARCHAR(20)   NOT NULL COMMENT 'CRM / CORE / OMS / MKT',
    source_name     VARCHAR(50)   NOT NULL COMMENT 'Feed name, e.g. CLIENT',
    target_table    VARCHAR(100)  NOT NULL COMMENT 'SCHEMA.TABLE inside WM_MICRO',
    stage_path      VARCHAR(200)  NOT NULL COMMENT 'Folder under @UTIL.STG_LANDING',
    file_format     VARCHAR(50)   NOT NULL COMMENT 'File format object in UTIL',
    file_pattern    VARCHAR(200)  NOT NULL COMMENT 'Regex for PATTERN =',
    on_error        VARCHAR(30)   NOT NULL DEFAULT 'ABORT_STATEMENT',
    load_order      NUMBER(3)     NOT NULL DEFAULT 1,
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    sla_hours       NUMBER(3)              COMMENT 'Expected freshness, used by dbt source freshness',
    description     VARCHAR(500),
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    CONSTRAINT pk_cntl_source_config PRIMARY KEY (source_system, source_name)
);

CREATE TABLE IF NOT EXISTS CNTL_BATCH_RUN (
    batch_id        VARCHAR(100)  NOT NULL COMMENT 'Task graph run id or dbt invocation_id',
    pipeline_name   VARCHAR(50)   NOT NULL COMMENT 'EOD_INGEST / DBT_BUILD / ...',
    target_name     VARCHAR(30)            COMMENT 'dbt target (dev/ci/prod) or SNOWFLAKE',
    invoked_by      VARCHAR(200),
    status          VARCHAR(30)   NOT NULL COMMENT 'RUNNING / SUCCEEDED / COMPLETED_WITH_ERRORS / FAILED',
    started_at      TIMESTAMP_NTZ NOT NULL,
    ended_at        TIMESTAMP_NTZ,
    files_loaded    NUMBER,
    rows_loaded     NUMBER,
    models_ok       NUMBER,
    models_failed   NUMBER,
    tests_passed    NUMBER,
    tests_warned    NUMBER,
    tests_failed    NUMBER,
    CONSTRAINT pk_cntl_batch_run PRIMARY KEY (batch_id)
);

CREATE TABLE IF NOT EXISTS CNTL_FILE_LOAD_AUDIT (
    audit_id        NUMBER        AUTOINCREMENT START 1 INCREMENT 1,   -- identity column
    batch_id        VARCHAR(100)  NOT NULL,
    source_system   VARCHAR(20)   NOT NULL,
    source_name     VARCHAR(50)   NOT NULL,
    target_table    VARCHAR(100)  NOT NULL,
    file_name       VARCHAR(500),
    status          VARCHAR(50)            COMMENT 'Loaded / Partially loaded / Load failed / PROC_ERROR',
    rows_parsed     NUMBER,
    rows_loaded     NUMBER,
    error_count     NUMBER,
    first_error     VARCHAR(2000),
    last_load_time  TIMESTAMP_LTZ,
    audited_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    CONSTRAINT pk_cntl_file_load_audit PRIMARY KEY (audit_id),
    CONSTRAINT fk_audit_batch FOREIGN KEY (batch_id) REFERENCES CNTL_BATCH_RUN (batch_id)
);

CREATE TABLE IF NOT EXISTS CNTL_WATERMARK (
    object_name       VARCHAR(200) NOT NULL COMMENT 'Fully qualified table the watermark belongs to',
    watermark_column  VARCHAR(100) NOT NULL,
    watermark_value   TIMESTAMP_NTZ,
    updated_by_batch  VARCHAR(100),
    updated_at        TIMESTAMP_NTZ,
    CONSTRAINT pk_cntl_watermark PRIMARY KEY (object_name)
);

CREATE TABLE IF NOT EXISTS CNTL_DQ_RESULT (
    batch_id        VARCHAR(100)  NOT NULL,
    test_unique_id  VARCHAR(500)  NOT NULL,
    test_name       VARCHAR(300),
    tested_model    VARCHAR(300),
    severity        VARCHAR(10),
    status          VARCHAR(20)            COMMENT 'pass / warn / fail / error',
    failures        NUMBER,
    executed_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    CONSTRAINT pk_cntl_dq_result PRIMARY KEY (batch_id, test_unique_id),
    CONSTRAINT fk_dq_batch FOREIGN KEY (batch_id) REFERENCES CNTL_BATCH_RUN (batch_id)
);

-- ---------------------------------------------------------------------------
-- Source feed configuration (the loader in 05 reads this; add a row = add a feed)
-- ---------------------------------------------------------------------------
MERGE INTO CNTL_SOURCE_CONFIG t
USING (
    SELECT * FROM VALUES
    -- system, name,               target,                     stage path,             format,          pattern,                     on_error,         order, sla, description
    ('CRM',  'BRANCH',             'RAW.CRM_BRANCH',             'crm/branch/',          'FF_CSV',        '.*[.]csv([.]gz)?',          'ABORT_STATEMENT', 1, 168, 'Branch master'),
    ('CRM',  'ADVISOR',            'RAW.CRM_ADVISOR',            'crm/advisor/',         'FF_CSV',        '.*[.]csv([.]gz)?',          'ABORT_STATEMENT', 2, 168, 'Relationship managers'),
    ('CRM',  'CLIENT',             'RAW.CRM_CLIENT',             'crm/client/',          'FF_CSV',        '.*[.]csv([.]gz)?',          'ABORT_STATEMENT', 3,  24, 'Client master (full + delta extracts)'),
    ('CRM',  'MEETING',            'RAW.CRM_MEETING',            'crm/meeting/',         'FF_NDJSON',     '.*[.]ndjson([.]gz)?',       'CONTINUE',        4,  24, 'Client-advisor meetings, newline-delimited JSON'),
    ('CORE', 'ACCOUNT',            'RAW.CORE_ACCOUNT',           'core/account/',        'FF_CSV',        '.*[.]csv([.]gz)?',          'ABORT_STATEMENT', 1,  24, 'Accounts'),
    ('CORE', 'ACCOUNT_HOLDER',     'RAW.CORE_ACCOUNT_HOLDER',    'core/account_holder/', 'FF_CSV',        '.*[.]csv([.]gz)?',          'ABORT_STATEMENT', 2,  24, 'Account ownership incl. joint holders'),
    ('CORE', 'APPLICATION_EVENT',  'RAW.CORE_APPLICATION_EVENT', 'core/application/',    'FF_CSV',        '.*[.]csv([.]gz)?',          'ABORT_STATEMENT', 3,  24, 'Account-opening workflow events'),
    ('OMS',  'TRANSACTION',        'RAW.OMS_TRANSACTION',        'oms/transaction/',     'FF_CSV',        '.*[.]csv([.]gz)?',          'CONTINUE',        1,  24, 'Trades and cash movements'),
    ('MKT',  'SECURITY',           'RAW.MKT_SECURITY',           'mkt/security/',        'FF_JSON_ARRAY', '.*[.]json([.]gz)?',         'ABORT_STATEMENT', 1, 168, 'Security master, JSON array with nested listings'),
    ('MKT',  'PRICE',              'RAW.MKT_PRICE',              'mkt/price/',           'FF_CSV',        '.*[.]csv([.]gz)?',          'ABORT_STATEMENT', 2,  24, 'Daily OHLC prices')
    AS s(source_system, source_name, target_table, stage_path, file_format, file_pattern, on_error, load_order, sla_hours, description)
) s
ON t.source_system = s.source_system AND t.source_name = s.source_name
WHEN MATCHED THEN UPDATE SET
    target_table = s.target_table, stage_path = s.stage_path, file_format = s.file_format,
    file_pattern = s.file_pattern, on_error = s.on_error, load_order = s.load_order,
    sla_hours = s.sla_hours, description = s.description
WHEN NOT MATCHED THEN INSERT
    (source_system, source_name, target_table, stage_path, file_format, file_pattern, on_error, load_order, sla_hours, description)
VALUES
    (s.source_system, s.source_name, s.target_table, s.stage_path, s.file_format, s.file_pattern, s.on_error, s.load_order, s.sla_hours, s.description);

SELECT * FROM CNTL_SOURCE_CONFIG ORDER BY source_system, load_order;
