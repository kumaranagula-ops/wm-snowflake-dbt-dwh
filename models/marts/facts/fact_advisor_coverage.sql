{#-
  FACT_ADVISOR_COVERAGE - FACTLESS FACT (coverage). Grain: advisor x client x month.
  Records which clients each advisor was RESPONSIBLE for in each month, whether or not
  anything happened. Coverage tables answer "what did NOT happen" questions:
     covered clients  MINUS  clients met (FACT_ADVISOR_MEETING)  =  clients nobody met
  See analyses/clients_not_met_this_month.sql
-#}
with months as (
    select month_end_trading_date,
           dateadd('second', 86399, month_end_trading_date::timestamp_ntz) as as_of_ts
    from {{ ref('int_month_end_dates') }}
)

select
    {{ date_key('mo.month_end_trading_date') }}          as month_date_key,
    coalesce(adv.advisor_key, {{ unknown_key() }})       as advisor_key,
    c.client_key
from months mo
join {{ ref('dim_client') }} c
  on  c.client_id <> -1
  and mo.as_of_ts >= c.valid_from
  and mo.as_of_ts <  c.valid_to
  and c.onboarded_date <= mo.month_end_trading_date
left join {{ ref('dim_advisor') }} adv on adv.advisor_id = c.primary_advisor_id
