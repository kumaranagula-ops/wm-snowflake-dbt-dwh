/* =====================================================================================
   L10_semi_structured.sql                    role: SYSADMIN   edition: any   trial: yes
   Prereq: core/05 loaded RAW.MKT_SECURITY (JSON array) and RAW.CRM_MEETING (NDJSON)
   Topics: VARIANT / OBJECT / ARRAY, path notation, casting, FLATTEN + LATERAL,
           nested arrays, building JSON (OBJECT_CONSTRUCT / ARRAY_AGG), TRY_PARSE_JSON,
           TYPEOF, STRIP_NULL_VALUE, schema-on-read vs schema-on-write
   ===================================================================================== */
USE ROLE SYSADMIN;
USE WAREHOUSE WM_TRANSFORM_WH;
USE SCHEMA WM_MICRO.RAW;

-- 1. Path notation and casting (keys are case-SENSITIVE; values come back as VARIANT)
SELECT payload,
       payload:ticker                      AS ticker_variant,     -- "INFY" (with quotes)
       payload:ticker::STRING              AS ticker,
       payload:attributes.face_value::INT  AS face_value,         -- nested object
       payload['asset_class']::STRING      AS asset_class,        -- bracket notation
       payload:listings[0]:exchange::STRING AS first_exchange,    -- array index
       ARRAY_SIZE(payload:listings)        AS listing_count,
       TYPEOF(payload:listings)            AS type_of_listings
FROM MKT_SECURITY;

-- 2. FLATTEN: one row per array element (LATERAL joins it back to its parent row)
SELECT s.payload:ticker::STRING      AS ticker,
       l.index                       AS listing_idx,
       l.value:exchange::STRING      AS exchange,
       l.value:symbol::STRING        AS exchange_symbol
FROM MKT_SECURITY s,
     LATERAL FLATTEN(INPUT => s.payload:listings) l;

-- Pivot the array back to columns (this is what dbt stg_mkt__security does)
SELECT s.payload:ticker::STRING AS ticker,
       MAX(IFF(l.value:exchange = 'NSE', l.value:symbol::STRING, NULL)) AS nse_symbol,
       MAX(IFF(l.value:exchange = 'BSE', l.value:symbol::STRING, NULL)) AS bse_code
FROM MKT_SECURITY s, LATERAL FLATTEN(s.payload:listings) l
GROUP BY 1;

-- 3. Arrays of scalars: meeting topics
SELECT m.payload:meeting_id::NUMBER AS meeting_id, t.value::STRING AS topic
FROM CRM_MEETING m, LATERAL FLATTEN(m.payload:topics) t;

SELECT t.value::STRING AS topic, COUNT(*) AS meetings
FROM CRM_MEETING m, LATERAL FLATTEN(m.payload:topics) t
GROUP BY 1 ORDER BY 2 DESC;

-- ARRAY_CONTAINS / filtering inside arrays
SELECT COUNT(*) FROM CRM_MEETING WHERE ARRAY_CONTAINS('TAX_PLANNING'::VARIANT, payload:topics);

-- 4. Discover keys in unknown JSON (RECURSIVE flatten)
SELECT DISTINCT f.path, TYPEOF(f.value) AS type
FROM MKT_SECURITY s, LATERAL FLATTEN(INPUT => s.payload, RECURSIVE => TRUE) f
ORDER BY 1;

-- 5. Build JSON from relational data (e.g. an API payload)
SELECT OBJECT_CONSTRUCT(
         'client_id', TRY_TO_NUMBER(c.client_id),
         'name',      ANY_VALUE(c.first_name || ' ' || c.last_name),
         'accounts',  ARRAY_AGG(DISTINCT TRY_TO_NUMBER(a.account_id))
       ) AS client_json
FROM CRM_CLIENT c
JOIN CORE_ACCOUNT a ON a.client_id = c.client_id
GROUP BY c.client_id
LIMIT 5;

-- 6. Bad JSON handling
SELECT TRY_PARSE_JSON('{"ok": 1}') AS good, TRY_PARSE_JSON('{oops') AS bad_returns_null;
SELECT STRIP_NULL_VALUE(PARSE_JSON('{"a": null}'):a) AS json_null_to_sql_null;

/* Notes
   * VARIANT holds up to 16 MB (compressed) per value. Snowflake auto-columnarises common
     keys inside VARIANT, so payload:ticker filters still prune micro-partitions.
   * Keep RAW as VARIANT (schema evolves without breaking loads), flatten in staging.
   * Parquet/Avro/ORC also load into VARIANT, or into typed columns with MATCH_BY_COLUMN_NAME.
   * XML: TYPE = XML file format + XMLGET / GET for parsing.                               */
