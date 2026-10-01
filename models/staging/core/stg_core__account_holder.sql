with source as (
    select * from {{ source('raw', 'core_account_holder') }}
)

select
    try_to_number(account_id)                       as account_id,
    try_to_number(client_id)                        as client_id,
    upper(trim(holder_role))                        as holder_role,
    try_to_number(ownership_pct, 5, 2) / 100        as ownership_share,   -- 60.00 -> 0.60
    _loaded_at
from source
qualify row_number() over (partition by account_id, client_id order by _loaded_at desc) = 1
