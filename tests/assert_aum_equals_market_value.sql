-- Bridge weighting check: AUM split across joint holders must add back to total market value
with pos as (
    select p.date_key, sum(p.market_value) mv
    from {{ ref('fact_daily_position') }} p
    where p.date_key in (select month_date_key from {{ ref('fact_client_aum_monthly') }})
    group by 1
), aum as (
    select month_date_key as date_key, sum(aum_inr) aum from {{ ref('fact_client_aum_monthly') }} group by 1
)
select pos.date_key, pos.mv, aum.aum
from pos join aum using (date_key)
where abs(pos.mv - aum.aum) > 1
