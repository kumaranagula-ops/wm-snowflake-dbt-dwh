select
    upper(trim(ticker))                       as ticker,
    price_date::date                          as price_date,
    close_price::number(18, 4)                as close_price
from {{ ref('raw_prices') }}
