-- Wealth accounts cannot short-sell: holdings never negative
select * from {{ ref('fact_daily_position') }} where quantity_held < 0
