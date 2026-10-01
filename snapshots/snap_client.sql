{#-
  SCD Type 2 history of clients. On every `dbt snapshot` / `dbt build`, dbt compares
  stg_crm__client to the snapshot table; when updated_at moved forward it closes the old
  row (dbt_valid_to) and inserts a new one.
  Tracks: risk_profile, segment, city, primary_advisor_id (advisor re-assignment!) ...
-#}
{% snapshot snap_client %}
{{
    config(
        unique_key='client_id',
        strategy='timestamp',
        updated_at='updated_at',
        hard_deletes='invalidate',
        dbt_valid_to_current="'9999-12-31 00:00:00'::timestamp_ntz"
    )
}}
select * exclude (_loaded_at) from {{ ref('stg_crm__client') }}
{% endsnapshot %}
