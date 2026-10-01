-- Control tables: what ran, what loaded, what failed
select * from {{ source('cntl', 'cntl_batch_run') }} order by started_at desc limit 20;
select source_system, source_name, count(*) files, sum(rows_loaded) rows_loaded, sum(error_count) errors
from {{ source('cntl', 'cntl_file_load_audit') }} group by 1, 2 order by 1, 2;
select * from {{ source('cntl', 'cntl_watermark') }};
select status, count(*) from {{ source('cntl', 'cntl_dq_result') }}
where batch_id = (select batch_id from {{ source('cntl', 'cntl_batch_run') }}
                  where pipeline_name like 'DBT%' order by started_at desc limit 1)
group by 1;
