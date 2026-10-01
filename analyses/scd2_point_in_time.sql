-- SCD2 in action: trades attributed to the advisor the client had AT TRADE TIME
select c.client_id, c.client_name, c.version_no, c.valid_from, c.valid_to, c.risk_profile,
       a.advisor_name, count(*) as trades, sum(f.gross_amount) as traded_amount
from {{ ref('fact_transaction') }} f
join {{ ref('dim_client') }}  c on c.client_key  = f.client_key
join {{ ref('dim_advisor') }} a on a.advisor_key = f.advisor_key
where c.client_id in (select client_id from {{ ref('dim_client') }} where version_no > 1)
group by all
order by c.client_id, c.version_no
