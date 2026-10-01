{#- DIM_TRANSACTION_TYPE - from a dbt seed (reference data the data team owns).
    position_direction / cash_direction turn raw quantities into signed measures in the fact. -#}
select
    {{ surrogate_key(['txn_type_code']) }}   as transaction_type_key,
    txn_type_code,
    txn_type_name,
    txn_category,
    position_direction,
    cash_direction,
    description
from {{ ref('ref_transaction_type') }}

union all
select {{ unknown_key() }}, 'UNKNOWN', 'Unknown', 'UNKNOWN', 0, 0, 'Not in reference data'
