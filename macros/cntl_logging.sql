{#-
  Writes dbt run metadata into the native Snowflake control tables (02_control_tables.sql):
    on-run-start -> CNTL_BATCH_RUN row with status RUNNING (batch_id = dbt invocation_id)
    on-run-end   -> closes that row with counts, writes one CNTL_DQ_RESULT row per test
  Every fact row also carries etl_batch_id = invocation_id, so any row can be traced to its run.
-#}
{% macro cntl_table(name) -%}
    {{ target.database }}.{{ var('cntl_schema') }}.{{ name }}
{%- endmacro %}

{% macro cntl_log_run_start() %}
    {% if var('cntl_logging') %}
        merge into {{ cntl_table('CNTL_BATCH_RUN') }} t
        using (select '{{ invocation_id }}' as batch_id) s on t.batch_id = s.batch_id
        when not matched then insert (batch_id, pipeline_name, target_name, invoked_by, status, started_at)
        values ('{{ invocation_id }}', 'DBT_{{ flags.WHICH | upper }}', '{{ target.name }}',
                current_user(), 'RUNNING', current_timestamp()::timestamp_ntz)
    {% else %}
        select 1
    {% endif %}
{% endmacro %}

{% macro cntl_log_run_end(results) %}
    {% if var('cntl_logging') and execute %}
        {% set ns = namespace(m_ok=0, m_err=0, t_pass=0, t_warn=0, t_fail=0) %}
        {% set dq_rows = [] %}
        {% for r in results %}
            {% set rt = r.node.resource_type %}
            {% if rt == 'test' %}
                {% if r.status == 'pass' %}{% set st = 'pass' %}{% set ns.t_pass = ns.t_pass + 1 %}
                {% elif r.status == 'warn' %}{% set st = 'warn' %}{% set ns.t_warn = ns.t_warn + 1 %}
                {% elif r.status == 'fail' %}{% set st = 'fail' %}{% set ns.t_fail = ns.t_fail + 1 %}
                {% elif r.status == 'error' %}{% set st = 'error' %}{% set ns.t_fail = ns.t_fail + 1 %}
                {% else %}{% set st = 'skipped' %}{% endif %}
                {% set tested = (r.node.depends_on.nodes | first) or '' %}
                {% set failures = r.failures if r.failures is not none else 'null' %}
                {% do dq_rows.append(
                    "('" ~ invocation_id ~ "', '" ~ r.node.unique_id | replace("'", "''") ~ "', '"
                    ~ r.node.name | replace("'", "''") ~ "', '" ~ tested | replace("'", "''") ~ "', '"
                    ~ (r.node.config.severity or '') ~ "', '" ~ st ~ "', " ~ failures ~ ")") %}
            {% elif rt in ['model', 'snapshot', 'seed'] %}
                {% if r.status == 'success' %}{% set ns.m_ok = ns.m_ok + 1 %}
                {% elif r.status == 'error' %}{% set ns.m_err = ns.m_err + 1 %}{% endif %}
            {% endif %}
        {% endfor %}

        {% if dq_rows | length > 0 %}
            {% do run_query(
                "insert into " ~ cntl_table('CNTL_DQ_RESULT')
                ~ " (batch_id, test_unique_id, test_name, tested_model, severity, status, failures) values "
                ~ dq_rows | join(', ')) %}
        {% endif %}

        update {{ cntl_table('CNTL_BATCH_RUN') }}
           set status        = '{{ "FAILED" if (ns.m_err + ns.t_fail) > 0 else ("COMPLETED_WITH_WARNINGS" if ns.t_warn > 0 else "SUCCEEDED") }}',
               ended_at      = current_timestamp()::timestamp_ntz,
               models_ok     = {{ ns.m_ok }},
               models_failed = {{ ns.m_err }},
               tests_passed  = {{ ns.t_pass }},
               tests_warned  = {{ ns.t_warn }},
               tests_failed  = {{ ns.t_fail }}
         where batch_id = '{{ invocation_id }}'
    {% else %}
        select 1
    {% endif %}
{% endmacro %}

{#- post-hook for incremental facts: record the high-water mark that was processed -#}
{% macro update_watermark(column='_loaded_at') %}
    {% if var('cntl_logging') %}
        merge into {{ cntl_table('CNTL_WATERMARK') }} w
        using (select '{{ this | upper }}' as object_name, max({{ column }}) as wm from {{ this }}) s
           on w.object_name = s.object_name
        when matched then update set
             watermark_value = s.wm, updated_by_batch = '{{ invocation_id }}', updated_at = current_timestamp()::timestamp_ntz
        when not matched then insert (object_name, watermark_column, watermark_value, updated_by_batch, updated_at)
             values (s.object_name, '{{ column | upper }}', s.wm, '{{ invocation_id }}', current_timestamp()::timestamp_ntz)
    {% else %}
        select 1
    {% endif %}
{% endmacro %}
