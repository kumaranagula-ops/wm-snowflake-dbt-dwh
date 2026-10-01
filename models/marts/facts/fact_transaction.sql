{#-
  FACT_TRANSACTION - TRANSACTION fact. Grain: one row per trade / cash movement (txn_id).
  * txn_id is a DEGENERATE dimension (an identifier with no dimension table of its own).
  * Every foreign key is NOT NULL: '-1' = unknown member, '-2' = not applicable.
  * Point-in-time join to SCD2 DIM_CLIENT -> client (and advisor) version valid at trade time.
  * Incremental MERGE on txn_id, driven by RAW._loaded_at with a small lookback window;
    the processed high-water mark is written to CNTL.CNTL_WATERMARK by a post-hook.
  Measures: quantity (additive), signed_quantity (additive), gross_amount / fees /
  net_cash_flow (additive), price (NON-additive: never SUM a price).
-#}
{{
    config(
        materialized='incremental',
        unique_key='txn_id',
        incremental_strategy='merge',
        cluster_by=['txn_date'],
        on_schema_change='append_new_columns',
        post_hook=["{{ update_watermark('_loaded_at') }}"]
    )
}}

with txns as (
    select * from {{ ref('stg_oms__transaction') }}
    {% if is_incremental() %}
    where _loaded_at > (
        select dateadd('hour', -{{ var('lookback_hours') }}, coalesce(max(_loaded_at), '1900-01-01'::timestamp_ntz))
        from {{ this }}
    )
    {% endif %}
)

select
    -- degenerate dimension
    t.txn_id,

    -- dimension keys (role-playing DIM_DATE twice)
    {{ date_key('t.txn_date') }}                                       as trade_date_key,
    {{ date_key('t.settle_date') }}                                    as settle_date_key,
    coalesce(a.account_key, {{ unknown_key() }})                       as account_key,
    coalesce(c.client_key, {{ unknown_key() }})                        as client_key,
    coalesce(adv.advisor_key, {{ unknown_key() }})                     as advisor_key,
    coalesce(a.branch_key, {{ unknown_key() }})                        as branch_key,
    case when t.ticker is null then '-2'
         else coalesce(s.security_key, {{ unknown_key() }}) end        as security_key,
    coalesce(tt.transaction_type_key, {{ unknown_key() }})             as transaction_type_key,
    coalesce(tp.trade_profile_key, {{ unknown_key() }})                as trade_profile_key,

    -- descriptive / convenience columns
    t.txn_type_code,
    t.txn_date,
    t.txn_ts,
    t.txn_status,

    -- measures
    t.quantity,
    t.quantity * coalesce(tt.position_direction, 0)                    as signed_quantity,
    t.price,
    t.gross_amount,
    t.fees,
    {{ money('t.gross_amount * coalesce(tt.cash_direction, 0) - t.fees') }} as net_cash_flow,

    -- lineage
    t._source_file,
    t._batch_id                                                        as raw_batch_id,
    t._loaded_at,
    '{{ invocation_id }}'                                              as etl_batch_id
from txns t
left join {{ ref('dim_transaction_type') }} tt on tt.txn_type_code = t.txn_type_code
left join {{ ref('dim_account') }}          a  on a.account_id     = t.account_id
left join {{ ref('int_account_primary_holder') }} ph on ph.account_id = t.account_id
left join {{ ref('dim_client') }}           c
       on c.client_id = ph.client_id
      and t.txn_ts >= c.valid_from
      and t.txn_ts <  c.valid_to
left join {{ ref('dim_advisor') }}          adv on adv.advisor_id  = c.primary_advisor_id
left join {{ ref('dim_security') }}         s   on s.ticker        = t.ticker
left join {{ ref('dim_trade_profile') }}    tp
       on tp.channel    = t.channel
      and tp.order_type = t.order_type
      and tp.is_advised = t.is_advised
