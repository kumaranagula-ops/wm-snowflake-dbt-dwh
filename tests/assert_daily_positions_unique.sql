select account_id, ticker, position_date, count(*) as n
from {{ ref('fct_daily_positions') }}
group by 1, 2, 3
having count(*) > 1
