{#- JSON security master: nested object (attributes) + array (listings) pivoted to columns -#}
with latest as (
    select payload, _loaded_at
    from {{ source('raw', 'mkt_security') }}
    qualify row_number() over (partition by payload:ticker::string order by _loaded_at desc) = 1
)

select
    upper(s.payload:ticker::string)                                   as ticker,
    s.payload:isin::string                                            as isin,
    s.payload:name::string                                            as security_name,
    upper(s.payload:asset_class::string)                              as asset_class,
    upper(s.payload:sector::string)                                   as sector,
    s.payload:attributes.face_value::number(18, 2)                    as face_value,
    s.payload:attributes.currency::string                             as currency,
    max(iff(l.value:exchange::string = 'NSE', l.value:symbol::string, null)) as nse_symbol,
    max(iff(l.value:exchange::string = 'BSE', l.value:symbol::string, null)) as bse_code,
    max(s._loaded_at)                                                 as _loaded_at
from latest s,
     lateral flatten(input => s.payload:listings) l
group by all
