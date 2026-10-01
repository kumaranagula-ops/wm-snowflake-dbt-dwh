with source as (
    select * from {{ source('raw', 'crm_advisor') }}
)

select
    try_to_number(advisor_id)                                     as advisor_id,
    initcap(trim(first_name)) || ' ' || initcap(trim(last_name))  as advisor_name,
    upper(trim(designation))                                      as designation,
    try_to_number(branch_id)                                      as branch_id,
    lower(trim(email))                                            as email,
    try_to_date(joined_date)                                      as joined_date,
    _loaded_at
from source
qualify row_number() over (partition by advisor_id order by _loaded_at desc, _file_row_number desc) = 1
