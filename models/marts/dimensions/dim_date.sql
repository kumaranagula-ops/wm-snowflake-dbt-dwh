{#-
  DIM_DATE - calendar dimension, one row per day 2015-01-01 .. 2030-12-31, built with
  Snowflake's GENERATOR (no source system needed).
  Key: date_key = YYYYMMDD integer (readable, sortable, partition friendly).
  Role-playing: facts join it several times (trade date, settle date, applied date ...).
  Row -1 = "unknown / not yet reached" (used by the accumulating snapshot fact).
-#}
with spine as (
    select dateadd(day, seq4(), '2015-01-01'::date) as date_day
    from table(generator(rowcount => 5844))
),

calendar as (
    select
        to_number(to_char(date_day, 'YYYYMMDD'))                       as date_key,
        date_day,
        dayname(date_day)                                              as day_name,
        dayofweekiso(date_day)                                         as day_of_week_iso,
        day(date_day)                                                  as day_of_month,
        dayofyear(date_day)                                            as day_of_year,
        date_trunc('week', date_day)::date                             as week_start_date,
        weekiso(date_day)                                              as iso_week,
        month(date_day)                                                as month_no,
        monthname(date_day)                                            as month_name,
        to_char(date_day, 'YYYY-MM')                                   as year_month,
        date_trunc('month', date_day)::date                            as month_start_date,
        last_day(date_day)                                             as month_end_date,
        quarter(date_day)                                              as quarter_no,
        year(date_day)                                                 as year_no,
        dayofweekiso(date_day) in (6, 7)                               as is_weekend,
        date_day = last_day(date_day)                                  as is_month_end,
        -- Indian financial year: April - March
        iff(month(date_day) >= 4, year(date_day), year(date_day) - 1)  as fiscal_year_start,
        'FY' || iff(month(date_day) >= 4, year(date_day), year(date_day) - 1) || '-'
             || right(iff(month(date_day) >= 4, year(date_day) + 1, year(date_day))::varchar, 2) as fiscal_year_label,
        mod(quarter(date_day) + 2, 4) + 1                              as fiscal_quarter_no
    from spine
    where date_day <= '2030-12-31'
)

select * from calendar
union all
select -1, null, 'Unknown', null, null, null, null, null, null, 'Unknown', 'Unknown', null, null,
       null, null, null, null, null, 'Unknown', null
