{{
  config(
    materialized='table',
    tags=['silver', 'customers']
  )
}}

-- Silver layer: Cleaned and standardized customer data
-- Deduplication, NULL handling, data quality rules

WITH source AS (
    SELECT * FROM {{ ref('bronze_customers') }}
),

cleaned AS (
    SELECT
        customer_id,
        TRIM(first_name) AS first_name,
        TRIM(last_name) AS last_name,
        LOWER(TRIM(email)) AS email,
        phone,
        UPPER(country) AS country,
        customer_segment,
        STR_TO_DATE(registration_date, '%Y-%m-%d') AS registration_date,
        CASE 
            WHEN COALESCE(change_type, 'insert') = 'deactivate' THEN FALSE
            WHEN is_active = 1 THEN TRUE
            ELSE FALSE 
        END AS is_active,
        COALESCE(change_type, 'insert') AS change_type,
        STR_TO_DATE(NULLIF(effective_at, ''), '%Y-%m-%dT%H:%i:%s') AS change_timestamp,
        CASE 
            WHEN COALESCE(change_type, 'insert') = 'deactivate' THEN 'deactivated'
            WHEN is_active = 1 THEN 'active'
            ELSE 'inactive'
        END AS lifecycle_state,
        batch_id,
        execution_date,
        ingestion_timestamp,
        CAST(NOW() AS DATETIME) AS transformation_timestamp,
        -- Data quality flags
        CASE
            WHEN customer_id IS NULL THEN 'missing_customer_id'
            WHEN email IS NULL THEN 'missing_email'
            WHEN LENGTH(email) < 5 OR email NOT LIKE '%@%' THEN 'invalid_email'
            ELSE NULL
        END AS data_quality_flag,
        -- Row number for deduplication
        ROW_NUMBER() OVER (
            PARTITION BY customer_id 
            ORDER BY 
                COALESCE(STR_TO_DATE(NULLIF(effective_at, ''), '%Y-%m-%dT%H:%i:%s'), ingestion_timestamp) DESC,
                ingestion_timestamp DESC
        ) AS row_num
    FROM source
    WHERE customer_id IS NOT NULL  -- Filter out records with missing customer_id
)

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
    change_timestamp,
    lifecycle_state,
    batch_id,
    execution_date,
    ingestion_timestamp,
    transformation_timestamp,
    data_quality_flag
FROM cleaned
WHERE row_num = 1  -- Keep only most recent record per customer
