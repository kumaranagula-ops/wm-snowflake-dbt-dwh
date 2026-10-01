{#-
  FACT_ADVISOR_MEETING - FACTLESS FACT (event tracking). Grain: one row per meeting.
  There is no numeric measure: the row itself IS the fact ("this client met this advisor on
  this day"). Questions are answered by COUNTing rows:
     meetings per advisor per month, % of HNI clients met this quarter, ...
-#}
select
    m.meeting_id,                                                      -- degenerate dimension
    {{ date_key('m.meeting_ts::date') }}                               as meeting_date_key,
    coalesce(c.client_key, {{ unknown_key() }})                        as client_key,
    coalesce(adv.advisor_key, {{ unknown_key() }})                     as advisor_key,
    m.meeting_channel,
    m.meeting_ts
from {{ ref('stg_crm__meeting') }} m
left join {{ ref('dim_client') }} c
       on c.client_id = m.client_id
      and m.meeting_ts >= c.valid_from
      and m.meeting_ts <  c.valid_to
left join {{ ref('dim_advisor') }} adv on adv.advisor_id = m.advisor_id
