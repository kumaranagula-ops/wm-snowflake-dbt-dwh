{#-
  BRIDGE_ACCOUNT_HOLDER - resolves the MANY-TO-MANY between accounts and clients
  (a joint account has several owners; a client can own several accounts).
  ownership_share is the WEIGHTING FACTOR: it sums to 1 per account, so
      SUM(market_value * ownership_share) per client never double counts a joint account.
  Joins to DIM_CLIENT on the durable client_id (DIM_CLIENT is SCD2: pick the version you need).
-#}
select
    {{ surrogate_key(['h.account_id']) }}   as account_key,
    h.account_id,
    h.client_id,
    h.holder_role,
    h.ownership_share
from {{ ref('stg_core__account_holder') }} h
