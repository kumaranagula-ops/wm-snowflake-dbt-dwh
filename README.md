# wm_micro — Snowflake + dbt micro project

A small, self-contained dbt project that runs **only on Snowflake** (no Airflow, no Docker, no Postgres).
Domain: a toy wealth-management book — clients, accounts, securities, trades, daily prices — modelled
into a star schema with SCD2, incremental MERGE, and a few Snowflake-native features.

```
seeds (RAW)  ──►  staging views (STAGING)  ──►  snapshot (SNAPSHOTS)  ──►  marts (MARTS)
raw_clients        stg_clients                  snap_clients (SCD2)        dim_client (SCD2)
raw_accounts       stg_accounts                                            dim_account
raw_securities     stg_securities                                          dim_security
raw_prices         stg_prices                                              dim_date (GENERATOR)
raw_transactions   stg_transactions (dedupe)                               fct_transactions (incremental MERGE)
                                                                           fct_daily_positions (ASOF JOIN)
                                                                           rpt_client_aum_daily (secure view)
                                                                           dt_account_cash_balance (dynamic table)
```

## What each piece demonstrates

| Feature | Where | Interview talking point |
|---|---|---|
| Seeds as raw layer | `seeds/` | Sample data with deliberate defects: a duplicate `txn_id`, a `'buy '` side value |
| Dedup with `QUALIFY` | `stg_transactions` | Snowflake filters on window functions without a sub-query |
| SCD Type 2 | `snap_clients` → `dim_client` | Timestamp strategy; first version back-dated so old trades still join |
| Point-in-time join | `fct_transactions` | Trade picks the client version valid at `txn_ts` |
| Incremental MERGE + lookback | `fct_transactions` | `unique_key`, `var('lookback_days')` for late-arriving trades |
| Clustering keys | `fct_transactions`, `fct_daily_positions` | `cluster_by` → micro-partition pruning on date |
| `ASOF JOIN` | `fct_daily_positions` | Latest position on/before each price date |
| `GENERATOR` date spine | `dim_date` | Calendar with Indian fiscal year, no packages |
| Secure view | `rpt_client_aum_daily` | Hides definition, blocks optimiser-based leakage |
| Dynamic table | `dt_account_cash_balance` | Snowflake refreshes it on `target_lag`, no scheduler |
| Permanent vs transient | `dbt_project.yml` (`+transient: false`) | dbt-snowflake defaults to transient tables (no Fail-safe) |
| Env isolation | `macros/generate_schema_name.sql` | `DEV_MARTS`, `CI_42_MARTS`, `MARTS` in one database |
| Zero-copy clone | `macros/clone_schema.sql` | `dbt run-operation clone_schema ...` |
| Custom generic test | `macros/tests/not_negative.sql` | Plus 3 singular tests in `tests/` |
| Time Travel, CHANGES, query_tag cost check | `analyses/` | Run `dbt compile`, paste into Snowsight |
| Key-pair auth + CI | `ci/`, `.github/workflows/dbt.yml` | PR → isolated `CI_<pr>` schemas, dropped after; main → prod |

## 1. One-time Snowflake setup

1. Run `setup/01_snowflake_setup.sql` in a Snowsight worksheet as ACCOUNTADMIN
   (set `SET MY_USER = '<your user>';` first). Creates `WM_WH` (XSMALL, 60 s auto-suspend),
   `WM_MICRO` database, `WM_TRANSFORMER` role and a 5-credit resource monitor.
2. Key-pair auth: follow `setup/02_keypair_auth.md`. You can reuse the key you already use for
   Aether Trade.

## 2. Run locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp profiles.yml.example ~/.dbt/profiles.yml
export SNOWFLAKE_ACCOUNT=<org-account>      # e.g. ABCDEFG-XY12345
export SNOWFLAKE_USER=<your user>
export SNOWFLAKE_PRIVATE_KEY_PATH=~/.snowflake/rsa_key.p8

dbt debug                 # connection check
dbt seed                  # -> WM_MICRO.DEV_RAW
dbt snapshot              # -> WM_MICRO.DEV_SNAPSHOTS
dbt build                 # models + tests (seeds/snapshot again too; harmless)
dbt docs generate && dbt docs serve   # lineage graph
```

Expected: 5 seeds, 1 snapshot, 13 models, 40 data tests.

## 3. Try the interesting parts

**SCD2 in action**
1. In `seeds/raw_clients.csv` change client 2's `risk_profile` to `MODERATE` and bump `updated_at`
   to e.g. `2026-10-01 10:00:00`.
2. `dbt seed --select raw_clients && dbt snapshot && dbt build --select dim_client+`
3. `select * from WM_MICRO.DEV_MARTS.DIM_CLIENT where client_id = 2;` → two rows, one `is_current`.

**Incremental MERGE**
1. Append a new trade row to `seeds/raw_transactions.csv` (new `txn_id`, recent `txn_ts`).
2. `dbt seed --select raw_transactions && dbt run --select fct_transactions`
3. Check Query History: you'll see a `MERGE INTO ... FCT_TRANSACTIONS` that touched only the
   lookback window. `dbt run --select fct_transactions --full-refresh` rebuilds from scratch.

**Dynamic table**
`select * from table(information_schema.dynamic_table_refresh_history()) order by refresh_start_time desc;`

## 4. CI/CD on GitHub

Add three repo secrets: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY`
(full contents of `rsa_key.p8`, including BEGIN/END lines).

* **Pull request** → `dbt build --target ci` into `CI_<pr number>_*` schemas, then drops them.
* **Push to main / manual run** → seed, snapshot, build into `RAW / STAGING / SNAPSHOTS / MARTS`.

## Cost notes

Everything runs on an XSMALL warehouse that suspends after 60 s; a full build is a few seconds of
compute. The dynamic table's `target_lag='1 day'` means at most one background refresh per day.
To stop it entirely: `alter dynamic table WM_MICRO.DEV_MARTS.DT_ACCOUNT_CASH_BALANCE suspend;`
To remove everything: `drop database WM_MICRO; drop warehouse WM_WH;`

## Layout

```
.github/workflows/dbt.yml     CI (PR) + prod deploy (main)
ci/profiles.yml               CI/prod targets, env-var driven
setup/                        Snowflake DDL + key-pair guide
seeds/                        raw CSVs + column types
models/staging/               views: clean, type, dedupe
models/marts/                 dims, facts, secure view, dynamic table
snapshots/                    SCD2 snapshot
macros/                       schema naming, clone, CI cleanup, money(), not_negative test
tests/                        singular data tests
analyses/                     Time Travel / CHANGES / clustering / cost queries
```
