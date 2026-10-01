{#- Latest version of each client. History (SCD2) is built by snapshots/snap_client. -#}
with source as (
    select * from {{ source('raw', 'crm_client') }}
)

select
    try_to_number(client_id)                 as client_id,
    initcap(trim(first_name))                as first_name,
    initcap(trim(last_name))                 as last_name,
    initcap(trim(first_name)) || ' ' || initcap(trim(last_name)) as client_name,
    lower(trim(email))                       as email,
    trim(phone)                              as phone,
    upper(trim(pan))                         as pan,
    try_to_date(date_of_birth)               as date_of_birth,
    initcap(trim(city))                      as city,           -- ' chennai ' -> 'Chennai'
    upper(trim(segment))                     as segment,
    upper(trim(risk_profile))                as risk_profile,   -- 'moderate' -> 'MODERATE'
    try_to_number(primary_advisor_id)        as primary_advisor_id,
    try_to_date(onboarded_date)              as onboarded_date,
    try_to_timestamp_ntz(updated_at)         as updated_at,
    _loaded_at
from source
qualify row_number() over (
    partition by client_id
    order by try_to_timestamp_ntz(updated_at) desc, _loaded_at desc
) = 1
