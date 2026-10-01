{#-
  Incremental MERGE on txn_id.
  * lookback window (var lookback_days) re-processes the last N days so late-arriving
    or corrected trades are upserted rather than missed.
  * cluster_by txn_date -> Snowflake micro-partition pruning on date filters.
  * point-in-time join to SCD2 dim_client picks the client version valid at trade time.
-#}
{{
    config(
        materialized='incremental',
        unique_key='txn_id',
        incremental_strategy='merge',
        cluster_by=['txn_date'],
        on_schema_change='append_new_columns'
    )
}}

with txns as (
    select * from {{ ref('stg_transactions') }}
    {% if is_incremental() %}
    where txn_date >= (
        select dateadd(day, -{{ var('lookback_days') }}, max(txn_date)) from {{ this }}
    )
    {% endif %}
)

select
    t.txn_id,
    to_number(to_char(t.txn_date, 'YYYYMMDD'))  as date_key,
    t.txn_date,
    t.txn_ts,
    t.account_id,
    a.client_id,
    c.client_sk,
    t.ticker,
    t.side,
    t.quantity,
    t.signed_quantity,
    t.price,
    t.fees,
    t.gross_amount,
    t.net_cash_flow,
    t.txn_status,
    current_timestamp()::timestamp_ntz          as dbt_loaded_at
from txns t
join {{ ref('dim_account') }} a
    on a.account_id = t.account_id
left join {{ ref('dim_client') }} c
    on  c.client_id = a.client_id
    and t.txn_ts >= c.valid_from
    and t.txn_ts <  c.valid_to
