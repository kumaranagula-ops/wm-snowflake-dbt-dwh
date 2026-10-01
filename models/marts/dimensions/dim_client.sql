{#-
  DIM_CLIENT - SCD Type 2 (one row per client VERSION), built from snapshots/snap_client.
    client_key  = surrogate key of the version (dbt_scd_id)   -> what facts store
    client_id   = durable business key (same for all versions) -> what the bridge uses
  The first version of each client is back-dated to 1900-01-01 so facts dated before the
  snapshot was first taken still find a version (otherwise they would fall to -1).
-#}
{{ config(post_hook="{{ apply_governance({'email': 'EMAIL', 'phone': 'PHONE', 'pan': 'PAN', 'date_of_birth': 'DOB'}, rap_column='primary_advisor_id') }}") }}

with snap as (
    select *,
           row_number() over (partition by client_id order by dbt_valid_from) as version_no
    from {{ ref('snap_client') }}
)

select
    dbt_scd_id                                                        as client_key,
    client_id,
    first_name,
    last_name,
    client_name,
    email,
    phone,
    pan,
    date_of_birth,
    city,
    segment,
    risk_profile,
    primary_advisor_id,
    onboarded_date,
    version_no,
    iff(version_no = 1, '1900-01-01'::timestamp_ntz, dbt_valid_from)  as valid_from,
    coalesce(dbt_valid_to, '9999-12-31'::timestamp_ntz)               as valid_to,
    coalesce(dbt_valid_to, '9999-12-31'::timestamp_ntz) = '9999-12-31'::timestamp_ntz as is_current
from snap

union all
select {{ unknown_key() }}, -1, null, null, 'Unknown', null, null, null, null, 'Unknown', 'Unknown', 'Unknown',
       -1, null, 1, '1900-01-01'::timestamp_ntz, '9999-12-31'::timestamp_ntz, true
