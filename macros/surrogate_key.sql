{#-
  Hash surrogate key: deterministic MD5 of the business key column(s).
  Same input -> same key on every rebuild, so facts and dims built in different runs
  still join. NULLs are replaced so (1, NULL) and (NULL, 1) don't collide.
  Unknown / missing members use the literal key '-1' (see unknown_member rows in dims).
-#}
{% macro surrogate_key(columns) -%}
    md5(concat_ws('||'
    {%- for c in columns -%}
        , coalesce(cast({{ c }} as varchar), '_null_')
    {%- endfor -%}
    ))
{%- endmacro %}

{% macro unknown_key() -%}'-1'{%- endmacro %}

{# YYYYMMDD integer key for DIM_DATE; -1 when the date is missing / not reached yet #}
{% macro date_key(col) -%}
    coalesce(to_number(to_char({{ col }}, 'YYYYMMDD')), -1)
{%- endmacro %}
