{#- dbt run-operation clone_schema --args '{source_schema: MARTS, target_schema: DEV_MARTS}'
    Zero-copy clone: instant, no extra storage until data diverges. -#}
{% macro clone_schema(source_schema, target_schema) %}
    {% do run_query("create or replace schema " ~ target.database ~ "." ~ target_schema
                    ~ " clone " ~ target.database ~ "." ~ source_schema) %}
    {{ log("Cloned " ~ source_schema ~ " -> " ~ target_schema, info=True) }}
{% endmacro %}
