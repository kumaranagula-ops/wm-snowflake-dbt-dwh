{#-
  Cleans the trade feed:
    * typed with TRY_ casts (bad values become NULL and are caught by tests, never fail the load)
    * 'buy ' -> 'BUY'
    * the same txn_id re-sent in a later file -> keep the latest load (QUALIFY)
-#}
with source as (
    select * from {{ source('raw', 'oms_transaction') }}
),

typed as (
    select
        try_to_number(txn_id)                       as txn_id,
        try_to_number(account_id)                   as account_id,
        upper(trim(txn_type))                       as txn_type_code,
        nullif(upper(trim(ticker)), '')             as ticker,
        try_to_number(quantity, 18, 4)              as quantity,
        try_to_number(price, 18, 4)                 as price,
        try_to_number(amount, 18, 2)                as amount,
        coalesce(try_to_number(fees, 18, 2), 0)     as fees,
        upper(trim(channel))                        as channel,
        coalesce(nullif(upper(trim(order_type)), ''), 'N/A') as order_type,
        try_to_timestamp_ntz(txn_ts)                as txn_ts,
        try_to_date(settle_date)                    as settle_date,
        upper(trim(status))                         as txn_status,
        _source_file,
        _file_row_number,
        _batch_id,
        _loaded_at
    from source
),

deduped as (
    select * from typed
    qualify row_number() over (partition by txn_id order by _loaded_at desc, _file_row_number desc) = 1
)

select
    * exclude (_file_row_number),
    txn_ts::date                                         as txn_date,
    channel = 'ADVISOR_DESK'                             as is_advised,
    {{ money('coalesce(amount, quantity * price)') }}    as gross_amount
from deduped
