{{
  config(
    materialized='table',
    tags=['gold', 'fact']
  )
}}

-- Gold layer: Orders fact table
-- Core business facts for analytics

SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_timestamp,
    o.order_status,
    o.order_amount,
    o.currency,
    o.payment_method,
    -- Derived metrics
    YEAR(o.order_date) AS order_year,
    QUARTER(o.order_date) AS order_quarter,
    MONTH(o.order_date) AS order_month,
    DAYOFWEEK(o.order_date) AS order_day_of_week,
    HOUR(o.order_timestamp) AS order_hour,
    -- Customer enrichment
    c.customer_segment,
    c.country,
    c.is_active AS customer_is_active,
    -- Metadata
    o.batch_id AS source_batch_id,
    o.transformation_timestamp AS updated_at
FROM {{ ref('silver_orders') }} o
INNER JOIN {{ ref('dim_customers') }} d
    ON o.customer_id = d.customer_id
LEFT JOIN {{ ref('silver_customers') }} c
    ON o.customer_id = c.customer_id
WHERE o.data_quality_flag IS NULL  -- Only clean records
