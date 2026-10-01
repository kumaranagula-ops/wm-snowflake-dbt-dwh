{#- Pivots the workflow event log (one row per event) into one row per application -#}
select
    application_id,
    any_value(client_id)                                           as client_id,
    any_value(requested_account_type)                              as requested_account_type,
    max(account_id)                                                as account_id,
    min(iff(event_type = 'APPLIED',        event_ts, null))        as applied_ts,
    min(iff(event_type = 'KYC_SUBMITTED',  event_ts, null))        as kyc_submitted_ts,
    min(iff(event_type = 'KYC_APPROVED',   event_ts, null))        as kyc_approved_ts,
    min(iff(event_type = 'ACCOUNT_OPENED', event_ts, null))        as account_opened_ts,
    min(iff(event_type = 'REJECTED',       event_ts, null))        as rejected_ts
from {{ ref('stg_core__application_event') }}
group by application_id
