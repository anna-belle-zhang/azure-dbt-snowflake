{{
  config(
    materialized='table',
    tags=['bronze', 'customers']
  )
}}

-- Bronze layer: Raw customer data from Parquet files
SELECT
    customer_id,
    first_name,
    last_name,
    email,
    phone,
    country,
    customer_segment,
    registration_date,
    is_active,
    change_type,
    effective_at,
    '{{ var("batch_id") }}' AS batch_id,
    '{{ var("execution_date") }}' AS execution_date,
    CURRENT_TIMESTAMP() AS ingestion_timestamp
FROM nocodb_db.src_customers
