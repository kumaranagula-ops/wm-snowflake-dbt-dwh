{#-
  DIM_TRADE_PROFILE - JUNK DIMENSION.
  channel, order_type and is_advised are low-cardinality flags. Instead of 3 tiny dims (or 3
  extra columns on a big fact), every combination that occurs gets one row and one key.
-#}
with combos as (
    select distinct channel, order_type, is_advised
    from {{ ref('stg_oms__transaction') }}
)

select
    {{ surrogate_key(['channel', 'order_type', 'is_advised']) }}   as trade_profile_key,
    channel,
    order_type,
    is_advised
from combos

union all
select {{ unknown_key() }}, 'UNKNOWN', 'UNKNOWN', false
