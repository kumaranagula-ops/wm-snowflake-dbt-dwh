{#-
  FACT_ACCOUNT_ONBOARDING - ACCUMULATING SNAPSHOT fact. Grain: one row per application.
  The row is UPDATED as the application moves through milestones (applied -> KYC submitted ->
  KYC approved -> account opened -> first funded). Milestones not reached yet point to date
  key -1. Lag measures (days between milestones) are what the business tracks.
  (Rebuilt as a table here; at scale it would be incremental MERGE on application_id.)
-#}
with m as (
    select * from {{ ref('int_application_milestones') }}
),

first_funding as (
    select account_key, min(txn_date) as first_funded_date
    from {{ ref('fact_transaction') }}
    where txn_type_code = 'DEPOSIT'
    group by 1
)

select
    m.application_id,                                                   -- degenerate dimension
    coalesce(c.client_key, {{ unknown_key() }})                         as client_key,
    iff(m.account_id is null, {{ unknown_key() }}, coalesce(a.account_key, {{ unknown_key() }})) as account_key,
    m.requested_account_type,

    {{ date_key('m.applied_ts::date') }}                                as applied_date_key,
    {{ date_key('m.kyc_submitted_ts::date') }}                          as kyc_submitted_date_key,
    {{ date_key('m.kyc_approved_ts::date') }}                           as kyc_approved_date_key,
    {{ date_key('m.account_opened_ts::date') }}                         as account_opened_date_key,
    {{ date_key('f.first_funded_date') }}                               as first_funded_date_key,
    {{ date_key('m.rejected_ts::date') }}                               as rejected_date_key,

    datediff('day', m.applied_ts, m.kyc_approved_ts)                    as days_to_kyc_approval,
    datediff('day', m.applied_ts, m.account_opened_ts)                  as days_to_account_open,
    datediff('day', m.account_opened_ts::date, f.first_funded_date)     as days_open_to_funded,

    case
        when m.rejected_ts       is not null then 'REJECTED'
        when f.first_funded_date is not null then 'FUNDED'
        when m.account_opened_ts is not null then 'ACCOUNT_OPENED'
        when m.kyc_approved_ts   is not null then 'KYC_APPROVED'
        when m.kyc_submitted_ts  is not null then 'KYC_SUBMITTED'
        else 'APPLIED'
    end                                                                 as current_stage,
    (m.rejected_ts is not null or f.first_funded_date is not null)      as is_closed_out
from m
left join {{ ref('dim_client') }} c
       on c.client_id = m.client_id
      and m.applied_ts >= c.valid_from
      and m.applied_ts <  c.valid_to
left join {{ ref('dim_account') }} a on a.account_id = m.account_id
left join first_funding f           on f.account_key = a.account_key
