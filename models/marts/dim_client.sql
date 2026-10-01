{#-
  SCD2 client dimension built on the snapshot.
  The first version of each client is back-dated to 1900-01-01 so that trades that
  happened before the snapshot was first taken still find a matching row.
-#}
with snap as (
    select
        *,
        row_number() over (partition by client_id order by dbt_valid_from) as version_no
    from {{ ref('snap_clients') }}
)

select
    dbt_scd_id                                                     as client_sk,
    client_id,
    client_name,
    city,
    risk_profile,
    onboarded_date,
    version_no,
    iff(version_no = 1, '1900-01-01'::timestamp_ntz, dbt_valid_from) as valid_from,
    coalesce(dbt_valid_to, '9999-12-31'::timestamp_ntz)               as valid_to,
    dbt_valid_to is null                                              as is_current
from snap
