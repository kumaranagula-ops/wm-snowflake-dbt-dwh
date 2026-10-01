{#-
  prod  -> custom schema used as-is            (RAW, STAGING, MARTS, SNAPSHOTS)
  other -> <target.schema>_<custom schema>     (DEV_RAW, DEV_STAGING, CI_123_MARTS ...)
  Keeps every developer / CI run isolated inside the same database.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
