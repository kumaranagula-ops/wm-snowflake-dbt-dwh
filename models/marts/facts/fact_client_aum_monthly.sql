{#-
  FACT_CLIENT_AUM_MONTHLY - AGGREGATE fact (pre-summarised for dashboards).
  Grain: client x month (month-end trading day; current month = month-to-date).
  Joint accounts are split with the bridge weighting factor (ownership_share), so the
  total AUM across all clients equals the total market value - no double counting.
-#}
with month_end_positions as (
    select me.month_end_trading_date,
           dateadd('second', 86399, me.month_end_trading_date::timestamp_ntz) as as_of_ts,
           p.account_key,
           p.security_key,
           p.market_value
    from {{ ref('int_month_end_dates') }} me
    join {{ ref('fact_daily_position') }} p on p.position_date = me.month_end_trading_date
)

select
    {{ date_key('mep.month_end_trading_date') }}                 as month_date_key,
    coalesce(c.client_key, {{ unknown_key() }})                  as client_key,
    coalesce(adv.advisor_key, {{ unknown_key() }})               as advisor_key,
    count(distinct mep.account_key)                              as accounts_held,
    count(distinct mep.security_key)                             as securities_held,
    {{ money('sum(mep.market_value * b.ownership_share)') }}     as aum_inr
from month_end_positions mep
join {{ ref('bridge_account_holder') }} b on b.account_key = mep.account_key
left join {{ ref('dim_client') }} c
       on c.client_id = b.client_id
      and mep.as_of_ts >= c.valid_from
      and mep.as_of_ts <  c.valid_to
left join {{ ref('dim_advisor') }} adv on adv.advisor_id = c.primary_advisor_id
group by 1, 2, 3
