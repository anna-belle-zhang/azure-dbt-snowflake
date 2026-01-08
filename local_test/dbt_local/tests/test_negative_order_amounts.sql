select
    *
from {{ ref("silver_orders") }}
where order_amount < 0
