-- Every cleaned staging transaction lands in the fact exactly once (no drops, no join fan-out)
with s as (select count(*) n, sum(gross_amount) amt from {{ ref('stg_oms__transaction') }}),
     f as (select count(*) n, sum(gross_amount) amt from {{ ref('fact_transaction') }})
select s.n as stg_rows, f.n as fact_rows, s.amt as stg_amount, f.amt as fact_amount
from s cross join f
where s.n <> f.n or s.amt <> f.amt
