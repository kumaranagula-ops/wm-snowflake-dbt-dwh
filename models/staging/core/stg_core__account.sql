with source as (
    select * from {{ source('raw', 'core_account') }}
)

select
    try_to_number(account_id)           as account_id,
    try_to_number(client_id)            as primary_client_id,
    upper(trim(account_type))           as account_type,
    upper(trim(currency))               as currency,
    upper(trim(status))                 as account_status,
    try_to_date(opened_date)            as opened_date,
    try_to_date(closed_date)            as closed_date,
    try_to_number(branch_id)            as branch_id,
    try_to_timestamp_ntz(updated_at)    as updated_at,
    _loaded_at
from source
qualify row_number() over (
    partition by account_id
    order by try_to_timestamp_ntz(updated_at) desc, _loaded_at desc
) = 1
