-- Right and wrong ways to aggregate a periodic snapshot (semi-additive) fact
-- WRONG: summing holdings across days multiplies the portfolio by the number of days
select sum(market_value) as wrong_total from {{ ref('fact_daily_position') }};
-- RIGHT: value on the latest day ...
select sum(market_value) as aum_latest
from {{ ref('fact_daily_position') }}
where position_date = (select max(position_date) from {{ ref('fact_daily_position') }});
-- ... or the average daily balance over a period
select avg(daily_mv) as avg_daily_aum
from (select position_date, sum(market_value) daily_mv from {{ ref('fact_daily_position') }} group by 1);
