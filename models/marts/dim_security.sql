select ticker, security_name, asset_class, sector
from {{ ref('stg_securities') }}
