{{
  config(
    materialized='table',
    tags=['bronze', 'orders']
  )
}}

-- Bronze layer: Raw order data from Parquet files
SELECT
    order_id,
    customer_id,
    order_date,
    order_timestamp,
    order_status,
    order_amount,
    currency,
    payment_method,
    '{{ var("batch_id") }}' AS batch_id,
    '{{ var("execution_date") }}' AS execution_date,
    CURRENT_TIMESTAMP() AS ingestion_timestamp
FROM nocodb_db.src_orders
