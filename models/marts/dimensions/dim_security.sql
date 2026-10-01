{#- DIM_SECURITY - flattened from the JSON security master (listings array pivoted to columns) -#}
select
    {{ surrogate_key(['ticker']) }}   as security_key,
    ticker,
    isin,
    security_name,
    asset_class,
    sector,
    face_value,
    currency,
    nse_symbol,
    bse_code
from {{ ref('stg_mkt__security') }}

union all
-- Unknown member: trades for a ticker that is not (yet) in the master land here instead of being dropped
select {{ unknown_key() }}, 'UNKNOWN', null, 'Unknown security', 'UNKNOWN', 'UNKNOWN', null, null, null, null
union all
-- Not-applicable member: cash movements (DEPOSIT / WITHDRAWAL / FEE) have no security at all
select '-2', 'N/A', null, 'Not applicable (cash movement)', 'CASH', 'N/A', null, null, null, null
