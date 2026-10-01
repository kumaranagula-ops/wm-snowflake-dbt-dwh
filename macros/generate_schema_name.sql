{#-
  prod  -> custom schema as-is            (STAGING, MARTS, SNAPSHOTS, SHARE, REF ...)
  other -> <target.schema>_<custom>       (DEV_MARTS, CI_42_MARTS ...)
  Every developer / CI run gets isolated schemas in the same database, while all of
  them read the same RAW + CNTL schemas that Snowflake loads natively.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
