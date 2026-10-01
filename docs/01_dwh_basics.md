# 1. Data warehouse basics, explained with this project

This page is for someone building their first warehouse. Every concept points to a real table in
this repo, so you can open the SQL and see it.

## 1.1 Why a data warehouse at all?

The source systems (CRM, core banking, order management, market data) are **OLTP** systems. They
are built to record one thing at a time quickly: "client 1002 bought 20 INFY". They are bad at
questions like "how did HNI clients' AUM change month over month, by advisor?". To answer that you
would have to join four systems that live in different databases and use different keys and
spellings, and keep history that the sources overwrite.

A **data warehouse (OLAP)** copies the data out, cleans and integrates it, keeps history, and
reshapes it so that analytical questions are simple and fast. Here, that whole job happens
**inside Snowflake**, with dbt doing the transformations.

## 1.2 Layers (and why there are several)

| Layer | Schema | Built by | What it holds | Rule |
|---|---|---|---|---|
| Landing / stage | `@UTIL.STG_LANDING` | you (PUT) / S3 | files exactly as received | never edit files |
| Raw | `RAW` | Snowflake COPY / Snowpipe | 1 table per feed, all VARCHAR / VARIANT, append-only, plus load metadata | load, never transform |
| Staging | `STAGING` | dbt views | typed, cleaned, de-duplicated, 1 model per raw table | no joins, no business logic |
| Intermediate | `INTERMEDIATE` | dbt (transient tables) | reusable building blocks (pivots, lookups) | not exposed to users |
| Snapshots | `SNAPSHOTS` | dbt snapshot | history of changing records (SCD2) | never rebuilt, only appended |
| Marts | `MARTS` | dbt tables | the dimensional model: `DIM_*`, `FACT_*`, `BRIDGE_*` | what BI tools read |
| Share | `SHARE` | dbt secure views | what other Snowflake accounts may see | no PII |
| Control | `CNTL` | Snowflake + dbt hooks | `CNTL_*` run logs, audit, watermarks, DQ results | for operations |
| Real-time | `RT` | streams, tasks, dynamic tables | intraday positions/exposure | runs beside the batch |

Why keep RAW untouched? If a transformation bug is found next month, you fix the SQL and rebuild
from RAW. You never need to ask the source system for the files again.

## 1.3 Dimensional modelling in one page

A **fact** is a measurement of a business event: a trade, a meeting, the value of a holding at the
end of a day. A **dimension** is the context you filter and group by: who, what, where, when.

```
              DIM_DATE           DIM_SECURITY
                   \                 /
   DIM_CLIENT ── FACT_TRANSACTION ── DIM_ACCOUNT ── DIM_BRANCH
                   /                 \
          DIM_ADVISOR            DIM_TRANSACTION_TYPE
```

### Grain: decide it first, always
The grain is the sentence that says what ONE row means. Every other design decision follows from it.

| Table | Grain |
|---|---|
| `FACT_TRANSACTION` | one trade or cash movement (`txn_id`) |
| `FACT_DAILY_POSITION` | one account × security × trading day |
| `FACT_CLIENT_AUM_MONTHLY` | one client × month end |
| `FACT_ACCOUNT_ONBOARDING` | one account application |
| `FACT_ADVISOR_MEETING` | one client-advisor meeting |
| `FACT_ADVISOR_COVERAGE` | one advisor × client × month |

### Keys

| Key type | Example | Why |
|---|---|---|
| Natural / business key | `client_id` from CRM | how the source identifies the thing |
| Surrogate key | `client_key`, `account_key` (MD5 hash) | warehouse-owned; stable even if sources change ids; one per SCD2 version |
| Durable key | `client_id` in `BRIDGE_ACCOUNT_HOLDER` | same for every version of a client |
| Degenerate dimension | `txn_id`, `meeting_id`, `application_id` in facts | an identifier with no attributes, so no dimension table |
| Date key | `20260930` (int) | readable, sortable, joins to `DIM_DATE` |
| Unknown / N/A member | `'-1'` unknown, `'-2'` not applicable, date key `-1` | facts never have NULL foreign keys and never silently drop rows |

### Star vs snowflake schema

* **Star**: each dimension is one flat, denormalised table that joins straight to the fact. Simple
  and fast. Most of this model is a star.
* **Snowflake**: a dimension is normalised into several tables. Here `DIM_ADVISOR → DIM_BRANCH`
  (and `DIM_ACCOUNT → DIM_BRANCH`) is snowflaked on purpose. Branch is shared by advisors and
  accounts, so it is stored once and referenced as an **outrigger**. The cost is one extra join.

### Fact table types (all five are in this project)

| Type | Table | How it behaves |
|---|---|---|
| Transaction | `FACT_TRANSACTION` | one row per event, inserted once, never updated (corrections MERGE by `txn_id`) |
| Periodic snapshot | `FACT_DAILY_POSITION` | one row per entity per period, even if nothing happened that day |
| Accumulating snapshot | `FACT_ACCOUNT_ONBOARDING` | one row per process instance, **updated** as milestones are reached; several date keys; lag measures |
| Factless (event) | `FACT_ADVISOR_MEETING` | records that something happened; no numeric measure, you `COUNT(*)` |
| Factless (coverage) | `FACT_ADVISOR_COVERAGE` | records what *could* happen (who is responsible for whom); used to find what did **not** happen |
| Aggregate | `FACT_CLIENT_AUM_MONTHLY` | pre-summarised fact for fast dashboards |

The classic factless question is in `analyses/clients_not_met_this_month.sql`: take the coverage
rows, subtract the meeting rows, and what's left is clients nobody met.

### Measure additivity

| Kind | Example | Safe to SUM over |
|---|---|---|
| Additive | `gross_amount`, `fees`, `net_cash_flow`, `quantity` | everything |
| Semi-additive | `quantity_held`, `market_value`, `aum_inr` | accounts / clients / securities, **not time** |
| Non-additive | `price`, `close_price`, ratios | nothing (use AVG / last value / recompute) |

`analyses/semi_additive_measures.sql` shows the wrong and right way to aggregate.

### Dimension techniques used

| Technique | Where | Explanation |
|---|---|---|
| SCD Type 1 (overwrite) | `DIM_ACCOUNT` | status CLOSED overwrites ACTIVE; no history |
| SCD Type 2 (new row per change) | `DIM_CLIENT` via `snap_client` | risk profile, segment, city, **advisor** changes keep history; `valid_from` / `valid_to` / `is_current` |
| Point-in-time join | facts → `DIM_CLIENT` | `txn_ts >= valid_from and txn_ts < valid_to` attaches the version valid at the time |
| Role-playing dimension | `DIM_DATE` | used as trade date, settle date, applied date, opened date ... |
| Junk dimension | `DIM_TRADE_PROFILE` | channel × order type × advised flag in one small table |
| Outrigger / snowflaked | `DIM_BRANCH` | referenced by other dimensions, not directly by facts (except as a convenience key) |
| Bridge table + weighting factor | `BRIDGE_ACCOUNT_HOLDER` | joint accounts (many-to-many). `ownership_share` sums to 1, so AUM is never double counted |
| Reference data via seed | `DIM_TRANSACTION_TYPE` | small lookup owned by the data team (`seeds/`) |
| Generated dimension | `DIM_DATE` | Snowflake `GENERATOR`, 2015-2030, Indian fiscal year |
| Unknown members | every `DIM_*` | rows with key `-1` (and `-2` = not applicable in `DIM_SECURITY`) |
| Late-arriving dimension | ticker `XYZLTD` | trade arrives before the security master knows it → `-1`, warning test |

### Conformed dimensions and the bus matrix
A **conformed** dimension means the same thing in every fact that uses it (one `DIM_CLIENT`, one
`DIM_DATE`). That's what lets you put meetings next to AUM next to trades in one report. The bus
matrix in [02_data_model.md](02_data_model.md) shows which fact uses which dimension.

## 1.4 Control (CNTL) tables

Operations people need to answer "did last night's load run, what did it load, what failed?".
They don't look at marts for that. They look at the control tables:

| Table | Written by | Answers |
|---|---|---|
| `CNTL_SOURCE_CONFIG` | you (02 script) | which feeds exist, where their files are, how to load them. Add a row to add a feed |
| `CNTL_BATCH_RUN` | EOD task graph + every dbt run (hooks) | when each pipeline ran, status, counts |
| `CNTL_FILE_LOAD_AUDIT` | `SP_LOAD_SOURCE` from `COPY_HISTORY` | every file: rows parsed/loaded, errors |
| `CNTL_WATERMARK` | dbt post-hook on `FACT_TRANSACTION` | how far incremental processing got |
| `CNTL_DQ_RESULT` | dbt on-run-end hook | every test result of every run |

Every fact row carries `etl_batch_id` (the dbt run id), and every RAW row carries `_batch_id` and
`_source_file`. So any number on a dashboard can be traced to the run and the exact file and line
it came from.

## 1.5 Incremental loading and data quality

* RAW is append-only, so staging uses `QUALIFY ROW_NUMBER() ... = 1` to keep the latest version of
  each key.
* `FACT_TRANSACTION` is incremental: each run only processes RAW rows loaded since the last
  watermark (minus a lookback window). It MERGEs on `txn_id`, so re-processing is safe
  (idempotent).
* There are about 135 tests. Generic tests (unique, not_null, relationships, accepted_values, plus
  custom `not_negative` and `sums_to_one`) and singular tests in `tests/` cover:
  * SCD2 integrity
  * staging-to-fact reconciliation
  * no short positions
  * bridge AUM = market value
  * milestone order

  Results land in `CNTL_DQ_RESULT`.
