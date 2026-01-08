{{ config(materialized="view") }}

select
    customer_segment,
    country,
    count(distinct order_id) as total_orders,
    sum(order_amount) as gross_revenue,
    avg(order_amount) as average_order_value,
    min(order_date) as first_order_date,
    max(order_date) as latest_order_date
from {{ ref("fct_orders") }}
group by 1, 2
