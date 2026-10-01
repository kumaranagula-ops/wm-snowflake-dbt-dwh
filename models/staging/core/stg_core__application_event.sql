with source as (
    select * from {{ source('raw', 'core_application_event') }}
)

select
    try_to_number(application_id)      as application_id,
    try_to_number(client_id)           as client_id,
    upper(trim(requested_account_type)) as requested_account_type,
    try_to_number(account_id)          as account_id,
    upper(trim(event_type))            as event_type,
    try_to_timestamp_ntz(event_ts)     as event_ts,
    _loaded_at
from source
qualify row_number() over (partition by application_id, upper(trim(event_type)) order by _loaded_at desc) = 1
