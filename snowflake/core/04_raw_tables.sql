/* =====================================================================================
   04_raw_tables.sql                          run as: SYSADMIN   edition: any   trial: yes
   -------------------------------------------------------------------------------------
   RAW layer design rules (why the tables look like this):

   1. Every business column is VARCHAR. A bad value (e.g. 'N/A' in a number column) can
      never fail the load; staging casts with TRY_TO_NUMBER / TRY_TO_DATE and tests catch it.
   2. Semi-structured feeds land in a single VARIANT column (PAYLOAD) - schema-on-read.
   3. RAW is append-only and keeps every version of every row ever received
      -> staging picks the latest, snapshots/SCD2 build history.
   4. Load metadata on every row (lineage back to the exact file + line + batch):
        _SOURCE_FILE         METADATA$FILENAME
        _FILE_ROW_NUMBER     METADATA$FILE_ROW_NUMBER
        _FILE_LAST_MODIFIED  METADATA$FILE_LAST_MODIFIED
        _BATCH_ID            CNTL_BATCH_RUN.batch_id
        _LOADED_AT           default CURRENT_TIMESTAMP -> drives dbt incremental watermark
   5. Business columns are in the SAME ORDER as the file. The loader (05) builds
      "$1, $2, ..." from INFORMATION_SCHEMA.COLUMNS, so column order matters and every
      metadata column starts with "_".
   ===================================================================================== */

USE ROLE SYSADMIN;
USE SCHEMA WM_MICRO.RAW;

-- ------------------------------------------------------------------ CRM
CREATE TABLE IF NOT EXISTS CRM_BRANCH (
    branch_id VARCHAR, branch_name VARCHAR, city VARCHAR, region VARCHAR, opened_date VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) COMMENT = 'CRM branch extract';

CREATE TABLE IF NOT EXISTS CRM_ADVISOR (
    advisor_id VARCHAR, first_name VARCHAR, last_name VARCHAR, designation VARCHAR, branch_id VARCHAR,
    email VARCHAR, joined_date VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) COMMENT = 'CRM relationship managers';

CREATE TABLE IF NOT EXISTS CRM_CLIENT (
    client_id VARCHAR, first_name VARCHAR, last_name VARCHAR, email VARCHAR, phone VARCHAR, pan VARCHAR,
    date_of_birth VARCHAR, city VARCHAR, segment VARCHAR, risk_profile VARCHAR, primary_advisor_id VARCHAR,
    onboarded_date VARCHAR, updated_at VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) COMMENT = 'CRM client master; full extract then deltas (append-only)';

CREATE TABLE IF NOT EXISTS CRM_MEETING (
    payload VARIANT,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) COMMENT = 'Client-advisor meetings (NDJSON -> VARIANT)';

-- ------------------------------------------------------------------ CORE banking
CREATE TABLE IF NOT EXISTS CORE_ACCOUNT (
    account_id VARCHAR, client_id VARCHAR, account_type VARCHAR, currency VARCHAR, status VARCHAR,
    opened_date VARCHAR, closed_date VARCHAR, branch_id VARCHAR, updated_at VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS CORE_ACCOUNT_HOLDER (
    account_id VARCHAR, client_id VARCHAR, holder_role VARCHAR, ownership_pct VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) COMMENT = 'Who owns which account, incl. joint holders (many-to-many)';

CREATE TABLE IF NOT EXISTS CORE_APPLICATION_EVENT (
    application_id VARCHAR, client_id VARCHAR, requested_account_type VARCHAR, account_id VARCHAR,
    event_type VARCHAR, event_ts VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) COMMENT = 'Account-opening workflow: APPLIED > KYC_SUBMITTED > KYC_APPROVED > ACCOUNT_OPENED | REJECTED';

-- ------------------------------------------------------------------ OMS (order management)
CREATE TABLE IF NOT EXISTS OMS_TRANSACTION (
    txn_id VARCHAR, account_id VARCHAR, txn_type VARCHAR, ticker VARCHAR, quantity VARCHAR, price VARCHAR,
    amount VARCHAR, fees VARCHAR, channel VARCHAR, order_type VARCHAR, txn_ts VARCHAR, settle_date VARCHAR,
    status VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) CHANGE_TRACKING = TRUE                  -- needed for streams / dynamic tables / CHANGES clause
  COMMENT = 'Trades (BUY/SELL) and cash movements (DEPOSIT/WITHDRAWAL/DIVIDEND/FEE)';

-- ------------------------------------------------------------------ MKT (market data)
CREATE TABLE IF NOT EXISTS MKT_SECURITY (
    payload VARIANT,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) COMMENT = 'Security master (JSON array, nested listings[])';

CREATE TABLE IF NOT EXISTS MKT_PRICE (
    ticker VARCHAR, price_date VARCHAR, open VARCHAR, high VARCHAR, low VARCHAR, close VARCHAR, volume VARCHAR,
    _source_file VARCHAR, _file_row_number NUMBER, _file_last_modified TIMESTAMP_NTZ, _batch_id VARCHAR,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
) CHANGE_TRACKING = TRUE;

SHOW TABLES IN SCHEMA WM_MICRO.RAW;
