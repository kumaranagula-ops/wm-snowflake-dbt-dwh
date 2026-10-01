{#-
  Snowflake DYNAMIC TABLE: Snowflake itself keeps this fresh (target_lag) by
  incrementally refreshing from fct_transactions - no scheduler needed.
  Kept at '1 day' lag on purpose so it costs almost nothing on a trial account.
-#}
{{
    config(
        materialized='dynamic_table',
        snowflake_warehouse='WM_WH',
        target_lag='1 day',
        refresh_mode='AUTO'
    )
}}

select
    account_id,
    client_id,
    count(*)               as txn_count,
    sum(net_cash_flow)     as net_cash_flow_inr,
    sum(fees)              as total_fees_inr,
    max(txn_ts)            as last_txn_ts
from {{ ref('fct_transactions') }}
group by account_id, client_id
