{#- One primary owner per account; used to attribute trades to a client -#}
select
    a.account_id,
    coalesce(h.client_id, a.primary_client_id) as client_id
from {{ ref('stg_core__account') }} a
left join {{ ref('stg_core__account_holder') }} h
    on  h.account_id  = a.account_id
    and h.holder_role = 'PRIMARY'
