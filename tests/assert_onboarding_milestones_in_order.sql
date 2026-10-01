-- Accumulating snapshot sanity: a later milestone can never be before an earlier one
select application_id
from {{ ref('fact_account_onboarding') }}
where (kyc_submitted_date_key  <> -1 and kyc_submitted_date_key  < applied_date_key)
   or (kyc_approved_date_key   <> -1 and kyc_approved_date_key   < kyc_submitted_date_key)
   or (account_opened_date_key <> -1 and account_opened_date_key < kyc_approved_date_key)
   or (first_funded_date_key   <> -1 and first_funded_date_key   < account_opened_date_key)
