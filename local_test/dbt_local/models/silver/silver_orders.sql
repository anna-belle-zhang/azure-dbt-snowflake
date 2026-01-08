{{
  config(
    materialized='table',
    tags=['silver', 'orders']
  )
}}

-- Silver layer: Cleaned and standardized order data
-- Deduplication, validation, type casting

WITH source AS (
    SELECT * FROM {{ ref('bronze_orders') }}
),

cleaned AS (
    SELECT
        order_id,
        customer_id,
        STR_TO_DATE(order_date, '%Y-%m-%d') AS order_date,
        STR_TO_DATE(order_timestamp, '%Y-%m-%dT%H:%i:%s') AS order_timestamp,
        order_status,
        CAST(order_amount AS DECIMAL(10,2)) AS order_amount,
        UPPER(currency) AS currency,
        payment_method,
        batch_id,
        execution_date,
        ingestion_timestamp,
        CAST(NOW() AS DATETIME) AS transformation_timestamp,
        -- Data quality flags
        CASE
            WHEN order_id IS NULL THEN 'missing_order_id'
            WHEN customer_id IS NULL THEN 'missing_customer_id'
            WHEN order_amount < 0 THEN 'negative_amount'
            WHEN order_amount > 10000 THEN 'suspiciously_high_amount'
            ELSE NULL
        END AS data_quality_flag,
        -- Row number for deduplication
        ROW_NUMBER() OVER (
            PARTITION BY order_id 
            ORDER BY ingestion_timestamp DESC
        ) AS row_num
    FROM source
    WHERE order_id IS NOT NULL
      AND order_amount >= 0  -- Filter out negative amounts
)

SELECT
    order_id,
    customer_id,
    order_date,
    order_timestamp,
    order_status,
    order_amount,
    currency,
    payment_method,
    batch_id,
    execution_date,
    ingestion_timestamp,
    transformation_timestamp,
    data_quality_flag
FROM cleaned
WHERE row_num = 1  -- Keep only most recent record per order
