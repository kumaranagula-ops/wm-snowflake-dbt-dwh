# 2. Data model: ER diagrams, table catalogue, bus matrix

GitHub renders the diagrams below. In VS Code, use a Mermaid preview extension. `dbt docs generate && dbt docs serve`
shows the same lineage interactively.

## 2.1 Overview: how the 16 mart tables connect

```mermaid
flowchart LR
    subgraph DIMENSIONS
        DD[DIM_DATE]
        DC[DIM_CLIENT<br/>SCD2]
        DA[DIM_ACCOUNT<br/>SCD1]
        DADV[DIM_ADVISOR]
        DB[DIM_BRANCH<br/>outrigger]
        DS[DIM_SECURITY]
        DT[DIM_TRANSACTION_TYPE<br/>seed]
        DTP[DIM_TRADE_PROFILE<br/>junk]
    end
    BR[BRIDGE_ACCOUNT_HOLDER<br/>weighting factor]
    subgraph FACTS
        FT[FACT_TRANSACTION<br/>transaction]
        FP[FACT_DAILY_POSITION<br/>periodic snapshot]
        FA[FACT_CLIENT_AUM_MONTHLY<br/>aggregate]
        FO[FACT_ACCOUNT_ONBOARDING<br/>accumulating snapshot]
        FM[FACT_ADVISOR_MEETING<br/>factless event]
        FC[FACT_ADVISOR_COVERAGE<br/>factless coverage]
    end
    DADV --> DB
    DA --> DB
    DA --- BR --- DC
    FT --> DD & DC & DA & DADV & DS & DT & DTP & DB
    FP --> DD & DA & DS
    FA --> DD & DC & DADV
    FO --> DD & DC & DA
    FM --> DD & DC & DADV
    FC --> DD & DC & DADV
```

## 2.2 ER diagram: trading star (transaction, positions, AUM)

![Trading star ER](images/er_trading_star.png)

Mermaid source (renders on GitHub):

```mermaid
erDiagram
    DIM_DATE {
        int date_key PK "YYYYMMDD, -1 = unknown"
        date date_day
        string year_month
        date month_end_date
        string fiscal_year_label "FY2026-27"
        boolean is_weekend
    }
    DIM_BRANCH {
        string branch_key PK
        int branch_id "natural key"
        string branch_name
        string city
        string region
    }
    DIM_ADVISOR {
        string advisor_key PK
        int advisor_id "natural key"
        string advisor_name
        string designation
        string branch_key FK
    }
    DIM_CLIENT {
        string client_key PK "one per version"
        int client_id "durable key"
        string client_name
        string segment
        string risk_profile
        int primary_advisor_id
        timestamp valid_from
        timestamp valid_to
        boolean is_current
    }
    DIM_ACCOUNT {
        string account_key PK
        int account_id "natural key"
        string account_type
        string account_status
        string branch_key FK
    }
    BRIDGE_ACCOUNT_HOLDER {
        string account_key FK
        int client_id "durable key to DIM_CLIENT"
        string holder_role "PRIMARY / JOINT"
        decimal ownership_share "sums to 1 per account"
    }
    DIM_SECURITY {
        string security_key PK "-1 unknown, -2 n/a"
        string ticker
        string isin
        string asset_class
        string sector
    }
    DIM_TRANSACTION_TYPE {
        string transaction_type_key PK
        string txn_type_code
        int position_direction
        int cash_direction
    }
    DIM_TRADE_PROFILE {
        string trade_profile_key PK
        string channel
        string order_type
        boolean is_advised
    }
    FACT_TRANSACTION {
        int txn_id PK "degenerate dimension"
        int trade_date_key FK
        int settle_date_key FK
        string account_key FK
        string client_key FK
        string advisor_key FK
        string branch_key FK
        string security_key FK
        string transaction_type_key FK
        string trade_profile_key FK
        decimal quantity "additive"
        decimal price "non-additive"
        decimal gross_amount "additive"
        decimal fees "additive"
        decimal net_cash_flow "additive"
        string etl_batch_id "-> CNTL_BATCH_RUN"
    }
    FACT_DAILY_POSITION {
        int date_key FK
        string account_key FK
        string security_key FK
        decimal quantity_held "semi-additive"
        decimal close_price "non-additive"
        decimal market_value "semi-additive"
    }
    FACT_CLIENT_AUM_MONTHLY {
        int month_date_key FK
        string client_key FK
        string advisor_key FK
        int accounts_held
        decimal aum_inr "semi-additive"
    }

    DIM_BRANCH ||--o{ DIM_ADVISOR : "employs"
    DIM_BRANCH ||--o{ DIM_ACCOUNT : "services"
    DIM_ACCOUNT ||--|{ BRIDGE_ACCOUNT_HOLDER : "owned by"
    DIM_CLIENT }|--o{ BRIDGE_ACCOUNT_HOLDER : "owns (client_id)"

    DIM_DATE ||--o{ FACT_TRANSACTION : "trade date"
    DIM_DATE ||--o{ FACT_TRANSACTION : "settle date"
    DIM_ACCOUNT ||--o{ FACT_TRANSACTION : "references"
    DIM_CLIENT ||--o{ FACT_TRANSACTION : "version at trade time"
    DIM_ADVISOR ||--o{ FACT_TRANSACTION : "advisor at trade time"
    DIM_BRANCH ||--o{ FACT_TRANSACTION : "references"
    DIM_SECURITY ||--o{ FACT_TRANSACTION : "references"
    DIM_TRANSACTION_TYPE ||--o{ FACT_TRANSACTION : "references"
    DIM_TRADE_PROFILE ||--o{ FACT_TRANSACTION : "references"

    DIM_DATE ||--o{ FACT_DAILY_POSITION : "references"
    DIM_ACCOUNT ||--o{ FACT_DAILY_POSITION : "references"
    DIM_SECURITY ||--o{ FACT_DAILY_POSITION : "references"

    DIM_DATE ||--o{ FACT_CLIENT_AUM_MONTHLY : "month end"
    DIM_CLIENT ||--o{ FACT_CLIENT_AUM_MONTHLY : "references"
    DIM_ADVISOR ||--o{ FACT_CLIENT_AUM_MONTHLY : "references"
```

## 2.3 ER diagram: relationship-management star (onboarding, meetings, coverage)

![Relationship management ER](images/er_relationship_mgmt.png)


```mermaid
erDiagram
    DIM_DATE {
        int date_key PK
    }
    DIM_CLIENT {
        string client_key PK
    }
    DIM_ADVISOR {
        string advisor_key PK
    }
    DIM_ACCOUNT {
        string account_key PK
    }

    FACT_ACCOUNT_ONBOARDING {
        int application_id PK "degenerate"
        string client_key FK
        string account_key FK "-1 until opened"
        int applied_date_key FK
        int kyc_submitted_date_key FK
        int kyc_approved_date_key FK
        int account_opened_date_key FK
        int first_funded_date_key FK
        int rejected_date_key FK
        int days_to_kyc_approval "lag measure"
        int days_to_account_open "lag measure"
        int days_open_to_funded "lag measure"
        string current_stage
    }
    FACT_ADVISOR_MEETING {
        int meeting_id PK "degenerate"
        int meeting_date_key FK
        string client_key FK
        string advisor_key FK
        string meeting_channel
    }
    FACT_ADVISOR_COVERAGE {
        int month_date_key FK
        string advisor_key FK
        string client_key FK
    }

    DIM_DATE ||--o{ FACT_ACCOUNT_ONBOARDING : "6 role-playing dates"
    DIM_CLIENT ||--o{ FACT_ACCOUNT_ONBOARDING : "references"
    DIM_ACCOUNT ||--o{ FACT_ACCOUNT_ONBOARDING : "references"
    DIM_DATE ||--o{ FACT_ADVISOR_MEETING : "references"
    DIM_CLIENT ||--o{ FACT_ADVISOR_MEETING : "references"
    DIM_ADVISOR ||--o{ FACT_ADVISOR_MEETING : "references"
    DIM_DATE ||--o{ FACT_ADVISOR_COVERAGE : "month"
    DIM_CLIENT ||--o{ FACT_ADVISOR_COVERAGE : "references"
    DIM_ADVISOR ||--o{ FACT_ADVISOR_COVERAGE : "references"
```

## 2.4 ER diagram: control tables

![Control tables ER](images/er_control_tables.png)


```mermaid
erDiagram
    CNTL_SOURCE_CONFIG {
        string source_system PK
        string source_name PK
        string target_table
        string stage_path
        string file_format
        string file_pattern
        string on_error
        boolean is_active
    }
    CNTL_BATCH_RUN {
        string batch_id PK "task graph run id / dbt invocation_id"
        string pipeline_name "EOD_INGEST, DBT_BUILD ..."
        string status
        timestamp started_at
        timestamp ended_at
        int files_loaded
        int rows_loaded
        int tests_failed
    }
    CNTL_FILE_LOAD_AUDIT {
        int audit_id PK
        string batch_id FK
        string source_system
        string source_name
        string file_name
        int rows_loaded
        int error_count
    }
    CNTL_WATERMARK {
        string object_name PK
        timestamp watermark_value
        string updated_by_batch
    }
    CNTL_DQ_RESULT {
        string batch_id PK
        string test_unique_id PK
        string tested_model
        string status
        int failures
    }
    CNTL_SOURCE_CONFIG ||--o{ CNTL_FILE_LOAD_AUDIT : "feed loaded"
    CNTL_BATCH_RUN ||--o{ CNTL_FILE_LOAD_AUDIT : "files in batch"
    CNTL_BATCH_RUN ||--o{ CNTL_DQ_RESULT : "tests in run"
    CNTL_BATCH_RUN ||--o{ CNTL_WATERMARK : "advanced by"
```

## 2.5 Table catalogue

| Table | Kind | Grain / purpose | Built from | Materialisation |
|---|---|---|---|---|
| `DIM_DATE` | dimension (generated, role-playing) | one day 2015-2030 + unknown | `GENERATOR` | table |
| `DIM_BRANCH` | dimension (outrigger) | one branch | RAW.CRM_BRANCH | table |
| `DIM_ADVISOR` | dimension, snowflaked to branch | one advisor | RAW.CRM_ADVISOR | table |
| `DIM_CLIENT` | dimension, SCD2 | one client version | RAW.CRM_CLIENT → `snap_client` | table |
| `DIM_ACCOUNT` | dimension, SCD1 | one account | RAW.CORE_ACCOUNT | table |
| `DIM_SECURITY` | dimension | one security (+ unknown, n/a) | RAW.MKT_SECURITY (JSON) | table |
| `DIM_TRANSACTION_TYPE` | dimension (reference) | one transaction type | `seeds/ref_transaction_type.csv` | table |
| `DIM_TRADE_PROFILE` | junk dimension | one channel × order type × advised combination | RAW.OMS_TRANSACTION | table |
| `BRIDGE_ACCOUNT_HOLDER` | bridge | one account × holder | RAW.CORE_ACCOUNT_HOLDER | table |
| `FACT_TRANSACTION` | transaction fact | one txn_id | RAW.OMS_TRANSACTION | **incremental MERGE**, clustered by txn_date |
| `FACT_DAILY_POSITION` | periodic snapshot | account × security × day | FACT_TRANSACTION + prices (ASOF JOIN) | table, clustered by position_date |
| `FACT_CLIENT_AUM_MONTHLY` | aggregate fact | client × month end | FACT_DAILY_POSITION + bridge | table |
| `FACT_ACCOUNT_ONBOARDING` | accumulating snapshot | one application | RAW.CORE_APPLICATION_EVENT + first deposit | table |
| `FACT_ADVISOR_MEETING` | factless (event) | one meeting | RAW.CRM_MEETING (NDJSON) | table |
| `FACT_ADVISOR_COVERAGE` | factless (coverage) | advisor × client × month | DIM_CLIENT (SCD2) | table |
| `SHARE.SHARE_CLIENT_AUM_MONTHLY` | secure view | client × month, no PII | FACT_CLIENT_AUM_MONTHLY | secure view |
| `CNTL_*` (5) | control | see 01_dwh_basics §1.4 | native DDL | permanent tables |
| `RT.INTRADAY_TRADE` + `RT.DT_*` (3) | real-time | intraday trades / positions / exposure | stream + triggered task, dynamic tables | native |

Plus 11 staging views, 3 intermediate transient tables and 1 snapshot table.

## 2.6 Bus matrix (which fact uses which conformed dimension)

| Fact \ Dimension | Date | Client | Account | Advisor | Branch | Security | Txn type | Trade profile |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| FACT_TRANSACTION | ✔ ✔ (trade, settle) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| FACT_DAILY_POSITION | ✔ | (via bridge) | ✔ | | | ✔ | | |
| FACT_CLIENT_AUM_MONTHLY | ✔ | ✔ | | ✔ | | | | |
| FACT_ACCOUNT_ONBOARDING | ✔ ×6 | ✔ | ✔ | | | | | |
| FACT_ADVISOR_MEETING | ✔ | ✔ | | ✔ | | | | |
| FACT_ADVISOR_COVERAGE | ✔ | ✔ | | ✔ | | | | |

## 2.7 How a question becomes SQL

*"Net cash flow by branch region and asset class for September, for UHNI clients, using the
segment they were in at the time of each trade"*

```sql
select b.region, s.asset_class, sum(f.net_cash_flow) as net_flow
from MARTS.FACT_TRANSACTION f
join MARTS.DIM_DATE     d on d.date_key     = f.trade_date_key
join MARTS.DIM_CLIENT   c on c.client_key   = f.client_key      -- version at trade time
join MARTS.DIM_BRANCH   b on b.branch_key   = f.branch_key
join MARTS.DIM_SECURITY s on s.security_key = f.security_key
where d.year_month = '2026-09' and c.segment = 'UHNI'
group by 1, 2;
```

Every join is fact → dimension on a single key, and filters sit on dimension attributes. That's
the whole point of a star schema.
