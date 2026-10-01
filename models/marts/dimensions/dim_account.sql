{#- DIM_ACCOUNT - SCD Type 1 (attributes overwritten, e.g. status ACTIVE -> CLOSED; no history kept) -#}
select
    {{ surrogate_key(['a.account_id']) }}                             as account_key,
    a.account_id,
    a.account_type,
    a.currency,
    a.account_status,
    a.account_status = 'ACTIVE'                                        as is_active,
    a.opened_date,
    a.closed_date,
    iff(b.branch_id is null, {{ unknown_key() }}, {{ surrogate_key(['b.branch_id']) }}) as branch_key
from {{ ref('stg_core__account') }} a
left join {{ ref('stg_crm__branch') }} b on b.branch_id = a.branch_id

union all
select {{ unknown_key() }}, -1, 'Unknown', null, 'Unknown', false, null, null, {{ unknown_key() }}
