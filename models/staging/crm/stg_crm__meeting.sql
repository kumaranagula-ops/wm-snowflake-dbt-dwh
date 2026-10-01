{#- NDJSON -> typed columns with VARIANT path notation -#}
with source as (
    select * from {{ source('raw', 'crm_meeting') }}
)

select
    payload:meeting_id::number                          as meeting_id,
    payload:client_id::number                           as client_id,
    payload:advisor_id::number                          as advisor_id,
    try_to_timestamp_ntz(payload:meeting_ts::string)    as meeting_ts,
    upper(payload:channel::string)                      as meeting_channel,
    payload:topics                                      as topics,          -- ARRAY kept for stg_crm__meeting_topic
    _loaded_at
from source
qualify row_number() over (partition by payload:meeting_id order by _loaded_at desc) = 1
