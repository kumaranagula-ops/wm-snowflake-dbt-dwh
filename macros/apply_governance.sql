{#-
  dbt rebuilds tables with CREATE OR REPLACE, which drops tags and policies attached to the
  old table. This post-hook re-attaches them after every build.
  Off by default (needs Enterprise edition + labs/L09_governance_security.sql).
  Usage in a model config:
     post_hook = "{{ apply_governance({'email': 'EMAIL', 'pan': 'PAN'}, rap_column='primary_advisor_id') }}"
-#}
{% macro apply_governance(pii_columns, rap_column=none) %}
    {% if var('enable_governance') and execute %}
        {% set gov = target.database ~ '.GOVERNANCE' %}
        {% for col, pii_type in pii_columns.items() %}
            {% do run_query("alter table " ~ this ~ " modify column " ~ col ~ " set tag " ~ gov ~ ".PII_TYPE = '" ~ pii_type ~ "'") %}
        {% endfor %}
        {% if rap_column %}
            {% do run_query("alter table " ~ this ~ " drop all row access policies") %}
            {% do run_query("alter table " ~ this ~ " add row access policy " ~ gov ~ ".RAP_ADVISOR_CLIENTS on (" ~ rap_column ~ ")") %}
        {% endif %}
    {% endif %}
    select 1
{% endmacro %}
