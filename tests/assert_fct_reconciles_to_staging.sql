-- Every cleaned trade must land in the fact table exactly once (no drops, no fan-out).
with s as (select count(*) as n from {{ ref('stg_transactions') }}),
     f as (select count(*) as n from {{ ref('fct_transactions') }})
select s.n as stg_rows, f.n as fct_rows
from s cross join f
where s.n <> f.n
