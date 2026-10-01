{#- Bridge weighting factors must add up to 1 per group (e.g. ownership per account) -#}
{% test sums_to_one(model, column_name, group_by) %}
    select {{ group_by }}, sum({{ column_name }}) as total
    from {{ model }}
    group by {{ group_by }}
    having abs(sum({{ column_name }}) - 1) > 0.0001
{% endtest %}
