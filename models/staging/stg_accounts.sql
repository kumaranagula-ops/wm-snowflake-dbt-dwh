select
    account_id::number            as account_id,
    client_id::number             as client_id,
    upper(trim(account_type))     as account_type,
    upper(trim(currency))         as currency,
    upper(trim(status))           as account_status,
    opened_date::date             as opened_date
from {{ ref('raw_accounts') }}
