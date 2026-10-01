-- SCD2 integrity: each client has exactly one current version and versions never overlap
select client_id, count_if(is_current) as current_versions
from {{ ref('dim_client') }}
where client_id <> -1
group by client_id
having count_if(is_current) <> 1
union all
select a.client_id, -1
from {{ ref('dim_client') }} a
join {{ ref('dim_client') }} b
  on a.client_id = b.client_id and a.client_key <> b.client_key
 and a.valid_from < b.valid_to and b.valid_from < a.valid_to
