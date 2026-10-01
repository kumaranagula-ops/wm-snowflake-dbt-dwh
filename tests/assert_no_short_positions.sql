-- Wealth-management accounts cannot be short: holdings must never go negative.
select *
from {{ ref('fct_daily_positions') }}
where quantity_held < 0
