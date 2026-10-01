{#-
  Daily holdings per account x security, valued at that day's close.
  Uses Snowflake ASOF JOIN: for every price date, take the latest cumulative
  position on or before that date (handles trades on days with no price).
-#}
{{ config(cluster_by=['position_date']) }}

with daily_change as (
    select account_id, ticker, txn_date, sum(signed_quantity) as qty_change
    from {{ ref('fct_transactions') }}
    group by 1, 2, 3
),

cumulative as (
    select
        account_id,
        ticker,
        txn_date,
        sum(qty_change) over (
            partition by account_id, ticker
            order by txn_date
            rows between unbounded preceding and current row
        ) as quantity_held
    from daily_change
),

first_trade as (
    select account_id, ticker, min(txn_date) as first_txn_date
    from daily_change
    group by 1, 2
),

spine as (
    select f.account_id, f.ticker, p.price_date as position_date, p.close_price
    from first_trade f
    join {{ ref('stg_prices') }} p
        on  p.ticker = f.ticker
        and p.price_date >= f.first_txn_date
)

select
    s.account_id,
    s.ticker,
    s.position_date,
    to_number(to_char(s.position_date, 'YYYYMMDD'))   as date_key,
    c.quantity_held,
    s.close_price,
    {{ money('c.quantity_held * s.close_price') }}    as market_value
from spine s
asof join cumulative c
    match_condition (s.position_date >= c.txn_date)
    on  s.account_id = c.account_id
    and s.ticker     = c.ticker
where c.quantity_held <> 0
