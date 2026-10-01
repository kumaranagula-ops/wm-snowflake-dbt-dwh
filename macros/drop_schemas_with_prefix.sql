{#-
  Cleans up throw-away CI schemas after a pull-request run.
  dbt run-operation drop_schemas_with_prefix --args '{prefix: CI_42}'
-#}
{% macro drop_schemas_with_prefix(prefix) %}
    {% set find %}
        select schema_name from {{ target.database }}.information_schema.schemata
        where schema_name ilike '{{ prefix }}%'
    {% endset %}
    {% for row in run_query(find) %}
        {% do run_query('drop schema if exists ' ~ target.database ~ '.' ~ row[0] ~ ' cascade') %}
        {{ log('Dropped ' ~ row[0], info=True) }}
    {% endfor %}
{% endmacro %}
