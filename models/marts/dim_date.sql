{#- Calendar built with Snowflake's GENERATOR table function (no package needed). -#}
with spine as (
    select dateadd(day, seq4(), '2015-01-01'::date) as date_day
    from table(generator(rowcount => 5844))      -- ~16 years
)

select
    to_number(to_char(date_day, 'YYYYMMDD'))  as date_key,
    date_day,
    year(date_day)                            as year_no,
    quarter(date_day)                         as quarter_no,
    month(date_day)                           as month_no,
    monthname(date_day)                       as month_name,
    dayofweekiso(date_day)                    as day_of_week_iso,
    dayofweekiso(date_day) in (6, 7)          as is_weekend,
    -- Indian financial year starts 1 April
    iff(month(date_day) >= 4, year(date_day), year(date_day) - 1) as fiscal_year_in
from spine
