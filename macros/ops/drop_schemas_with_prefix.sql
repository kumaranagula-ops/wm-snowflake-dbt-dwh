{#- Cleans up CI schemas after a pull-request run:
    dbt run-operation drop_schemas_with_prefix --args '{prefix: CI_42}' -#}
{% macro drop_schemas_with_prefix(prefix) %}
    {% set rows = run_query("select schema_name from " ~ target.database ~ ".information_schema.schemata where startswith(schema_name, '" ~ prefix | upper ~ "_')") %}
    {% for row in rows %}
        {% do run_query("drop schema if exists " ~ target.database ~ "." ~ row[0] ~ " cascade") %}
        {{ log("Dropped " ~ row[0], info=True) }}
    {% endfor %}
{% endmacro %}
