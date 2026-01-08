{{
  config(
    materialized='table',
    tags=['gold', 'dimension']
  )
}}

-- Gold layer: Customer dimension
-- Clean dimension table for analytics

SELECT
    customer_id,
    first_name,
    last_name,
    CONCAT(first_name, ' ', last_name) AS full_name,
    email,
    phone,
    country,
    customer_segment,
    registration_date,
    is_active,
    change_type,
    change_timestamp,
    lifecycle_state,
    CASE
        WHEN lifecycle_state = 'deactivated' THEN 'Former Customer'
        WHEN is_active THEN 'Active'
        ELSE 'Inactive'
    END AS customer_status,
    DATEDIFF(CURRENT_DATE(), registration_date) AS days_since_registration,
    YEAR(registration_date) AS registration_year,
    QUARTER(registration_date) AS registration_quarter,
    batch_id AS source_batch_id,
    transformation_timestamp AS updated_at
FROM {{ ref('silver_customers') }}
WHERE data_quality_flag IS NULL  -- Only clean records in gold layer
