{#- One row per meeting x topic: LATERAL FLATTEN explodes the JSON array -#}
select
    m.meeting_id,
    t.index                as topic_seq,
    t.value::string        as topic
from {{ ref('stg_crm__meeting') }} m,
     lateral flatten(input => m.topics) t
