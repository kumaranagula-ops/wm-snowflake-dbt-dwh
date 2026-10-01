{#-
  FACT_DAILY_POSITION - PERIODIC SNAPSHOT fact. Grain: account x security x trading day.
  A row exists for every trading day an account holds a security, even with no trade that day.
  quantity_held / market_value are SEMI-ADDITIVE: you can SUM across accounts or securities,
  but NOT across days (summing Monday + Tuesday holdings is meaningless -> use the last day
  or an average).
  Snowflake ASOF JOIN: for each price date take the latest cumulative position on/before it.
-#}
{{ config(cluster_by=['position_date']) }}

with trades as (
    select f.account_key, f.security_key, s.ticker, f.txn_date, sum(f.signed_quantity) as qty_change
    from {{ ref('fact_transaction') }} f
    join {{ ref('dim_security') }} s on s.security_key = f.security_key
    where f.signed_quantity <> 0
      and f.security_key not in ('-1', '-2')
    group by 1, 2, 3, 4
),

cumulative as (
    select account_key, security_key, txn_date,
           sum(qty_change) over (partition by account_key, security_key order by txn_date
                                 rows between unbounded preceding and current row) as quantity_held
    from trades
),

first_trade as (
    select account_key, security_key, ticker, min(txn_date) as first_txn_date
    from trades
    group by 1, 2, 3
),

spine as (
    select ft.account_key, ft.security_key, p.price_date, p.close_price
    from first_trade ft
    join {{ ref('stg_mkt__price') }} p
      on p.ticker = ft.ticker
     and p.price_date >= ft.first_txn_date
)

select
    {{ date_key('s.price_date') }}                       as date_key,
    s.account_key,
    s.security_key,
    s.price_date                                         as position_date,
    c.quantity_held,
    s.close_price,
    {{ money('c.quantity_held * s.close_price') }}       as market_value
from spine s
asof join cumulative c
    match_condition (s.price_date >= c.txn_date)
    on  s.account_key  = c.account_key
    and s.security_key = c.security_key
where c.quantity_held <> 0
