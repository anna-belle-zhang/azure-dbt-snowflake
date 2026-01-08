{{
  config(
    materialized='view',
    tags=['semantic', 'customer_metrics']
  )
}}

-- Semantic layer: Customer-level metrics

SELECT
    c.customer_id,
    c.full_name,
    c.email,
    c.country,
    c.customer_segment,
    c.registration_date,
    c.days_since_registration,
    -- Order metrics
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(CASE WHEN o.order_status = 'completed' THEN 1 ELSE 0 END) AS completed_orders,
    SUM(CASE WHEN o.order_status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_orders,
    SUM(o.order_amount) AS total_revenue,
    AVG(o.order_amount) AS avg_order_value,
    MAX(o.order_date) AS last_order_date,
    MIN(o.order_date) AS first_order_date,
    DATEDIFF(CURRENT_DATE(), MAX(o.order_date)) AS days_since_last_order,
    -- Customer classification
    CASE
        WHEN COUNT(DISTINCT o.order_id) = 0 THEN 'Never Ordered'
        WHEN DATEDIFF(CURRENT_DATE(), MAX(o.order_date)) > 90 THEN 'Inactive'
        WHEN DATEDIFF(CURRENT_DATE(), MAX(o.order_date)) <= 30 THEN 'Active'
        ELSE 'At Risk'
    END AS customer_status
FROM {{ ref('dim_customers') }} c
LEFT JOIN {{ ref('fact_orders') }} o
    ON c.customer_id = o.customer_id
GROUP BY
    c.customer_id,
    c.full_name,
    c.email,
    c.country,
    c.customer_segment,
    c.registration_date,
    c.days_since_registration
