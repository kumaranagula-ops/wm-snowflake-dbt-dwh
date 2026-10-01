{#-
  Zero-copy clone a schema (Snowflake metadata-only copy, no storage cost until data diverges).
  Usage:
    dbt run-operation clone_schema --args '{source_schema: MARTS, target_schema: DEV_MARTS_CLONE}'
-#}
{% macro clone_schema(source_schema, target_schema) %}
    {% set sql %}
        create or replace schema {{ target.database }}.{{ target_schema }}
        clone {{ target.database }}.{{ source_schema }};
    {% endset %}
    {% do run_query(sql) %}
    {{ log("Cloned " ~ source_schema ~ " -> " ~ target_schema, info=True) }}
{% endmacro %}
