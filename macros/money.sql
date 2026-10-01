{% macro money(expr, scale=2) -%}
    cast(round({{ expr }}, {{ scale }}) as number(18, {{ scale }}))
{%- endmacro %}
