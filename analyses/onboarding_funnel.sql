-- Accumulating snapshot: funnel + average lag between milestones
select
    current_stage,
    count(*)                         as applications,
    round(avg(days_to_kyc_approval), 1)  as avg_days_to_kyc,
    round(avg(days_to_account_open), 1)  as avg_days_to_open,
    round(avg(days_open_to_funded), 1)   as avg_days_open_to_funded
from {{ ref('fact_account_onboarding') }}
group by 1
order by applications desc
