select
    upper(trim(ticker))         as ticker,
    trim(security_name)         as security_name,
    upper(trim(asset_class))    as asset_class,
    upper(trim(sector))         as sector
from {{ ref('raw_securities') }}
