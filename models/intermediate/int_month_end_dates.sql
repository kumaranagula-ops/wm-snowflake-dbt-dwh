{#- Last trading day of each month that has prices (the current month = month-to-date) -#}
select
    date_trunc('month', price_date)   as month_start_date,
    max(price_date)                   as month_end_trading_date
from {{ ref('stg_mkt__price') }}
group by 1
