{#-
  SCD Type 2 history of client attributes (risk_profile, city ...).
  Timestamp strategy: a new version is captured whenever updated_at moves forward.
-#}
{% snapshot snap_clients %}
{{
    config(
        unique_key='client_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=True
    )
}}
select * from {{ ref('stg_clients') }}
{% endsnapshot %}
