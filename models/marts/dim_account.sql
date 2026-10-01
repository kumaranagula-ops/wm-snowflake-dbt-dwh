select
    account_id,
    client_id,
    account_type,
    currency,
    account_status,
    opened_date
from {{ ref('stg_accounts') }}
