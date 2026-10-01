with source as (
    select * from {{ source('raw', 'mkt_price') }}
)

select
    upper(trim(ticker))                 as ticker,
    try_to_date(price_date)             as price_date,
    try_to_number(open, 18, 4)          as open_price,
    try_to_number(high, 18, 4)          as high_price,
    try_to_number(low, 18, 4)           as low_price,
    try_to_number(close, 18, 4)         as close_price,
    try_to_number(volume)               as volume,
    _loaded_at
from source
qualify row_number() over (partition by upper(trim(ticker)), try_to_date(price_date) order by _loaded_at desc) = 1
