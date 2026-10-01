{#-
  Cleans raw trade feed:
    * normalises side ('buy ' -> 'BUY')
    * removes duplicate loads of the same txn_id (QUALIFY = Snowflake window filter)
    * derives signed quantity and cash-flow amounts
-#}
with source as (
    select * from {{ ref('raw_transactions') }}
),

cleaned as (
    select
        txn_id::number                         as txn_id,
        account_id::number                     as account_id,
        upper(trim(ticker))                    as ticker,
        upper(trim(side))                      as side,
        quantity::number(18, 4)                as quantity,
        price::number(18, 4)                   as price,
        coalesce(fees, 0)::number(18, 2)       as fees,
        txn_ts::timestamp_ntz                  as txn_ts,
        upper(trim(status))                    as txn_status
    from source
)

select
    *,
    txn_ts::date                                                    as txn_date,
    iff(side = 'BUY', quantity, -quantity)                          as signed_quantity,
    {{ money('quantity * price') }}                                 as gross_amount,
    {{ money("iff(side = 'BUY', -(quantity * price) - fees, (quantity * price) - fees)") }} as net_cash_flow
from cleaned
qualify row_number() over (partition by txn_id order by txn_ts desc) = 1
