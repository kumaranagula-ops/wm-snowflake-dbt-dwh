{#-
  Secure view exposed through Snowflake Secure Data Sharing (snowflake/labs/L07_data_sharing.sql).
  No PII: client_id + segment only. "secure" hides the SQL and blocks optimizer side-channels.
-#}
select
    d.month_end_date,
    d.year_month,
    c.client_id,
    c.segment,
    c.risk_profile,
    f.accounts_held,
    f.aum_inr
from {{ ref('fact_client_aum_monthly') }} f
join {{ ref('dim_client') }} c on c.client_key = f.client_key
join {{ ref('dim_date') }}   d on d.date_key   = f.month_date_key
