select account_key, security_key, date_key, count(*) n
from {{ ref('fact_daily_position') }}
group by 1, 2, 3 having count(*) > 1
