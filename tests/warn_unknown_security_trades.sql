{{ config(severity='warn') }}
-- Late-arriving dimension: trades whose ticker is not in the security master (security_key = -1)
select txn_id, txn_date, _source_file
from {{ ref('fact_transaction') }}
where security_key = '-1'
