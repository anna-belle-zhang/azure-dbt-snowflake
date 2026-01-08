{{ config(materialized="table") }}

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_timestamp,
    o.order_status,
    o.order_amount,
    o.currency,
    o.payment_method,
    c.customer_segment,
    c.country,
    o.batch_id,
    o.ingestion_timestamp as ingested_at
from {{ ref("silver_orders") }} o
left join {{ ref("silver_customers") }} c on o.customer_id = c.customer_id
