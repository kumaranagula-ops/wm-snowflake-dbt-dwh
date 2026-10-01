select
    client_id::number                         as client_id,
    initcap(trim(first_name))                 as first_name,
    initcap(trim(last_name))                  as last_name,
    initcap(trim(first_name)) || ' ' || initcap(trim(last_name)) as client_name,
    initcap(trim(city))                       as city,
    upper(trim(risk_profile))                 as risk_profile,
    onboarded_date::date                      as onboarded_date,
    updated_at::timestamp_ntz                 as updated_at
from {{ ref('raw_clients') }}
