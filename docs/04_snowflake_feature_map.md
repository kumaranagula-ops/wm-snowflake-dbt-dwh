# 4. Snowflake feature map: where each topic lives in this repo

Edition: **Std** = Standard, **Ent** = Enterprise, **BC** = Business Critical. "Trial" says whether
it runs on a single trial account with nothing else needed. Snowflake trials let you pick
Enterprise, which unlocks the Ent rows.

## Architecture and compute
| Topic | Where | Edition | Trial |
|---|---|---|---|
| Virtual warehouses, auto-suspend/resume, per-workload sizing | core/00 | Std | ✔ |
| Multi-cluster warehouses (scale out) | core/00 (comment), labs/L12 | Ent | ✔ Ent |
| Resource monitors | core/00 | Std | ✔ |
| Budgets | labs/L13 (note) | Std | ✔ |
| Query acceleration service | labs/L12 | Ent | ✔ Ent |
| Caching: result / warehouse / metadata | labs/L12 | Std | ✔ |
| Micro-partitions, pruning, clustering keys, automatic clustering | dbt `cluster_by`, labs/L12 | Std | ✔ |
| Search optimization service | labs/L12 | Ent | ✔ Ent |
| Materialized views | labs/L12, core/08 comparison | Ent | ✔ Ent |

## Storage and data protection
| Topic | Where | Edition | Trial |
|---|---|---|---|
| Permanent / transient / temporary tables and schemas | core/00 (SCRATCH), dbt `+transient`, labs/L05 | Std | ✔ |
| Time Travel (AT / BEFORE, OFFSET / TIMESTAMP / STATEMENT) | labs/L05 | Std (1 day) / Ent (90) | ✔ |
| UNDROP table / schema / database | labs/L05 | Std | ✔ |
| Data retention parameters, MIN_DATA_RETENTION | core/00, labs/L05 | Std / Ent | ✔ |
| Fail-safe | labs/L05 (+ storage metrics) | Std | ✔ (view only) |
| Zero-copy cloning: table / schema / database, clone + Time Travel | labs/L05, dbt macro `clone_schema` | Std | ✔ |
| Replication groups | labs/L08 | Std | ✘ needs 2nd account |
| Failover groups, client redirect | labs/L08 | BC | ✘ |

## Data movement: loading
| Topic | Where | Edition | Trial |
|---|---|---|---|
| File formats CSV / JSON / NDJSON / Parquet | core/03 | Std | ✔ |
| Internal named stage, user stage, table stage, directory tables | core/03, labs/L01 | Std | ✔ |
| PUT (snow CLI), LIST, REMOVE, querying staged files | scripts/upload_batch.sh, core/03 | Std | ✔ |
| COPY INTO with transformations + METADATA$ columns | core/05 | Std | ✔ |
| Metadata-driven loading (config table + stored procedure) | core/02, core/05 | Std | ✔ |
| ON_ERROR, VALIDATION_MODE, VALIDATE(), FORCE, PURGE, load metadata (64 days) | labs/L01 | Std | ✔ |
| INFER_SCHEMA, CREATE TABLE USING TEMPLATE, MATCH_BY_COLUMN_NAME | labs/L01 | Std | ✔ |
| COPY_HISTORY / LOAD_HISTORY | core/05, labs/L01 | Std | ✔ |
| Storage integration + external stage (S3) | labs/L02 | Std | ✘ needs AWS |
| Snowpipe auto-ingest (S3 → SQS), PIPE_STATUS, REFRESH | labs/L02 | Std | ✘ needs AWS |
| Snowpipe REST API / Snowpipe Streaming | labs/L01, L02 (notes) | Std | n/a |
| External tables | labs/L02 | Std | ✘ needs AWS |
| Iceberg tables | labs/L02 (note) | Std | n/a |

## Data movement: unloading and sharing
| Topic | Where | Edition | Trial |
|---|---|---|---|
| COPY INTO @stage: CSV / Parquet, SINGLE, MAX_FILE_SIZE, PARTITION BY, HEADER | labs/L06 | Std | ✔ |
| GET to local | labs/L06 | Std | ✔ |
| Unload to S3 | labs/L06 (comment) | Std | ✘ needs AWS |
| Secure Data Sharing: shares, secure views, consumers | labs/L07, dbt `share/` | Std | partly |
| Database roles in shares | labs/L07 | Std | ✔ (provider side) |
| Reader (managed) accounts | labs/L07 | Std | may be blocked on trial |
| Multi-tenant share via CURRENT_ACCOUNT() | labs/L07 (pattern) | Std | n/a |
| Marketplace / listings | labs/L07 (note) | Std | n/a |

## Change data capture and pipelines
| Topic | Where | Edition | Trial |
|---|---|---|---|
| Standard stream, METADATA$ACTION / ISUPDATE / ROW_ID | core/07, labs/L03 | Std | ✔ |
| Append-only stream, SHOW_INITIAL_ROWS | core/07 | Std | ✔ |
| Insert-only stream (external table) | labs/L02 | Std | ✘ needs AWS |
| Stream on view, CHANGES clause, staleness, offsets in transactions | labs/L03 | Std | ✔ |
| Tasks: scheduled (interval / CRON + time zone) | core/06, labs/L04 | Std | ✔ |
| Task graph (DAG), multiple predecessors, finalizer task | core/06 | Std | ✔ |
| Serverless tasks | core/06 (TSK_LOAD_MKT), labs/L04 | Std | ✔ |
| WHEN SYSTEM$STREAM_HAS_DATA, stream-triggered tasks | core/07, labs/L04 | Std | ✔ |
| Task return values, graph config, retries, auto-suspend on failures | core/06, labs/L04 | Std | ✔ |
| Dynamic tables, TARGET_LAG / DOWNSTREAM, refresh modes, chains | core/08 | Std | ✔ |
| Dynamic tables vs streams+tasks vs materialized views | core/08 header | n/a | n/a |
| Alerts + email notifications | labs/L13 | Std | ✔ |

## Programming
| Topic | Where | Edition | Trial |
|---|---|---|---|
| Snowflake Scripting procedures (cursor, RESULTSET, EXECUTE IMMEDIATE, exceptions) | core/05, labs/L11 | Std | ✔ |
| Owner's vs caller's rights | core/05, labs/L11 | Std | ✔ |
| SQL UDF, UDTF, secure UDF | labs/L11 | Std | ✔ |
| Python UDF, Python (Snowpark) procedure | labs/L11 | Std | ✔ (Anaconda terms) |
| Sequences, AUTOINCREMENT / IDENTITY | core/02, labs/L11 | Std | ✔ |
| Semi-structured: VARIANT, path notation, FLATTEN, LATERAL, ARRAY/OBJECT functions | dbt staging, labs/L10 | Std | ✔ |
| QUALIFY, ASOF JOIN, GENERATOR, GROUP BY ALL, EXCLUDE | dbt models | Std | ✔ |

## Security and governance
| Topic | Where | Edition | Trial |
|---|---|---|---|
| RBAC: system roles, custom functional roles, hierarchy | core/01 | Std | ✔ |
| Future grants (schema vs database level) | core/01 | Std | ✔ |
| Key-pair authentication (dbt, CI) | profiles, ci/, README | Std | ✔ |
| Object tagging | labs/L09 | Std | ✔ |
| Dynamic data masking, tag-based masking | labs/L09, dbt `apply_governance` | Ent | ✔ Ent |
| Row access policies + mapping table | labs/L09 | Ent | ✔ Ent |
| Projection / aggregation policies, classification, ACCESS_HISTORY | labs/L09 (notes) | Ent | ✔ Ent |
| Network policies, MFA, encryption, Tri-Secret Secure | labs/L09 (notes) | Std / BC | n/a |

## Monitoring and cost
| Topic | Where | Edition | Trial |
|---|---|---|---|
| INFORMATION_SCHEMA vs ACCOUNT_USAGE | labs/L13 | Std | ✔ |
| Credits by warehouse, serverless features, storage | labs/L13, labs/L05 | Std | ✔ |
| Query tags (set in dbt profiles) and finding slow queries | profiles, labs/L12, L13 | Std | ✔ |
| Task / DT / pipe / copy history | core/06, core/08, labs/L02 | Std | ✔ |

## dbt-on-Snowflake specifics
| Topic | Where |
|---|---|
| `generate_schema_name` for dev / ci / prod isolation | macros/generate_schema_name.sql |
| Incremental `merge` + `unique_key` + lookback + watermark | fact_transaction |
| Snapshots (SCD2), `hard_deletes`, `dbt_valid_to_current` | snapshots/snap_client.sql |
| Snowflake configs: `cluster_by`, `transient`, `copy_grants`, `secure`, `grants`, `query_tag` | dbt_project.yml, models |
| Dynamic table materialization | core/08 (note) |
| Hooks writing to control tables | macros/cntl_logging.sql |
| Post-hooks re-applying tags / policies | macros/apply_governance.sql |
| Sources + freshness, seeds, exposures, analyses | models/staging/_sources.yml, seeds/, models/exposures.yml, analyses/ |
| Generic + custom generic + singular tests (~135) | `_*.yml`, macros/tests, tests/ |
