-- Factless COVERAGE minus factless EVENT = "what did not happen"
-- Which clients was each advisor responsible for last month but never met?
with last_month as (
    select max(month_date_key) as month_date_key from {{ ref('fact_advisor_coverage') }}
),
covered as (
    select cov.advisor_key, cov.client_key, d.month_start_date, d.month_end_date
    from {{ ref('fact_advisor_coverage') }} cov
    join last_month lm on lm.month_date_key = cov.month_date_key
    join {{ ref('dim_date') }} d on d.date_key = cov.month_date_key
),
met as (
    select distinct m.advisor_key, c.client_id, d.month_start_date
    from {{ ref('fact_advisor_meeting') }} m
    join {{ ref('dim_client') }} c on c.client_key = m.client_key
    join {{ ref('dim_date') }}   d on d.date_key   = m.meeting_date_key
)
select a.advisor_name, c.client_id, c.client_name, c.segment
from covered cv
join {{ ref('dim_client') }}  c on c.client_key  = cv.client_key
join {{ ref('dim_advisor') }} a on a.advisor_key = cv.advisor_key
left join met on met.advisor_key = cv.advisor_key
             and met.client_id   = c.client_id
             and met.month_start_date = cv.month_start_date
where met.client_id is null
order by a.advisor_name, c.segment desc
