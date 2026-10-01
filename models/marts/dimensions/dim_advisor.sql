{#-
  DIM_ADVISOR - relationship managers. Normalised: carries branch_key instead of copying
  branch name/city/region -> DIM_ADVISOR -> DIM_BRANCH is a SNOWFLAKE-schema branch.
  (In a pure star you would flatten branch_name/region into this table.)
-#}
select
    {{ surrogate_key(['a.advisor_id']) }}                          as advisor_key,
    a.advisor_id,
    a.advisor_name,
    a.designation,
    a.email,
    a.joined_date,
    iff(b.branch_id is null, {{ unknown_key() }}, {{ surrogate_key(['b.branch_id']) }}) as branch_key
from {{ ref('stg_crm__advisor') }} a
left join {{ ref('stg_crm__branch') }} b on b.branch_id = a.branch_id

union all
select {{ unknown_key() }}, -1, 'Unknown', 'Unknown', null, null, {{ unknown_key() }}
