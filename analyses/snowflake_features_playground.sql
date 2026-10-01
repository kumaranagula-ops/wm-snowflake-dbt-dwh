-- `dbt compile` renders this to target/compiled/... ; paste into Snowsight to try.
-- None of it runs as part of `dbt build`.

-- 1. Time Travel: table as it was 10 minutes ago
select count(*) from {{ ref('fct_transactions') }} at(offset => -60*10);

-- 2. What changed in the last hour (needs change_tracking, which the dynamic table enables)
select * from {{ ref('fct_transactions') }}
  changes(information => default) at(offset => -3600);

-- 3. Zero-copy clone for a safe experiment
create or replace table {{ target.database }}.{{ target.schema }}.fct_transactions_clone
  clone {{ ref('fct_transactions') }};

-- 4. Is clustering doing anything?
select system$clustering_information('{{ ref('fct_transactions') }}', '(txn_date)');

-- 5. Which dbt queries cost the most? (query_tag set in profiles.yml)
select query_text, total_elapsed_time/1000 as secs, bytes_scanned, partitions_scanned, partitions_total
from snowflake.account_usage.query_history
where query_tag = 'dbt_wm_micro'
order by start_time desc
limit 20;

-- 6. Dynamic table refresh history
select * from table(information_schema.dynamic_table_refresh_history())
order by refresh_start_time desc limit 10;
