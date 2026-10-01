{#-
  Reporting layer exposed as a SECURE view: definition hidden from consumers and
  optimiser cannot leak data through predicate push-down.
-#}
{{ config(materialized='view', secure=true) }}

select
    p.position_date,
    c.client_id,
    c.client_name,
    c.risk_profile,
    s.asset_class,
    count(distinct p.ticker)     as positions,
    sum(p.market_value)          as aum_inr
from {{ ref('fct_daily_positions') }} p
join {{ ref('dim_account') }}  a on a.account_id = p.account_id
join {{ ref('dim_client') }}   c on c.client_id  = a.client_id and c.is_current
join {{ ref('dim_security') }} s on s.ticker     = p.ticker
group by all
