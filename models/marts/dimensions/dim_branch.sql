{#- DIM_BRANCH - outrigger of DIM_ADVISOR and DIM_ACCOUNT (this is the "snowflaked" part of the model) -#}
select
    {{ surrogate_key(['branch_id']) }}   as branch_key,
    branch_id,
    branch_name,
    city,
    region,
    opened_date
from {{ ref('stg_crm__branch') }}

union all
select {{ unknown_key() }}, -1, 'Unknown', 'Unknown', 'Unknown', null
