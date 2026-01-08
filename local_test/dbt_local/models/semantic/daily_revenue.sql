{{
  config(
    materialized='view',
    tags=['semantic', 'revenue_metrics']
  )
}}

-- Semantic layer: Daily revenue metrics

SELECT
    order_date,
    order_year,
    order_quarter,
    order_month,
    country,
    customer_segment,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS unique_customers,
    SUM(CASE WHEN order_status = 'completed' THEN order_amount ELSE 0 END) AS completed_revenue,
    SUM(CASE WHEN order_status = 'pending' THEN order_amount ELSE 0 END) AS pending_revenue,
    SUM(order_amount) AS total_revenue,
    AVG(order_amount) AS avg_order_value,
    MAX(order_amount) AS max_order_value,
    MIN(order_amount) AS min_order_value
FROM {{ ref('fact_orders') }}
GROUP BY
    order_date,
    order_year,
    order_quarter,
    order_month,
    country,
    customer_segment
