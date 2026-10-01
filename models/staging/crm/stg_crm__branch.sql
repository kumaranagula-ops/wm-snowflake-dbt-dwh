with source as (
    select * from {{ source('raw', 'crm_branch') }}
)

select
    try_to_number(branch_id)      as branch_id,
    trim(branch_name)             as branch_name,
    initcap(trim(city))           as city,
    upper(trim(region))           as region,
    try_to_date(opened_date)      as opened_date,
    _loaded_at
from source
-- RAW is append-only: keep the latest version of each branch
qualify row_number() over (partition by branch_id order by _loaded_at desc, _file_row_number desc) = 1
