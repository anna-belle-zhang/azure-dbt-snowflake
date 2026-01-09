{{
  config(
    materialized='view',
    tags=['gold', 'dimension', 'scd2']
  )
}}

-- Slowly changing dimension (Type 2) for customers.
-- Builds history from bronze change-events so we can time-travel per customer.

WITH source_events AS (
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
            WHEN change_type = 'deactivate' THEN FALSE
            WHEN is_active = 1 THEN TRUE
            ELSE FALSE
        END AS is_active,
        COALESCE(change_type, 'insert') AS change_type,
        STR_TO_DATE(NULLIF(effective_at, ''), '%Y-%m-%dT%H:%i:%s') AS change_timestamp,
        batch_id,
        execution_date,
        ingestion_timestamp
    FROM {{ ref('bronze_customers') }}
    WHERE customer_id IS NOT NULL
),

ordered_events AS (
    SELECT
        source_events.*,
        COALESCE(change_timestamp, ingestion_timestamp) AS event_ts
    FROM source_events
),

scd AS (
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
        event_ts AS valid_from,
        LEAD(event_ts) OVER (
            PARTITION BY customer_id
            ORDER BY event_ts ASC, ingestion_timestamp ASC
        ) AS valid_to_exclusive,
        batch_id,
        execution_date,
        ingestion_timestamp
    FROM ordered_events
)

SELECT
    customer_id,
    first_name,
    last_name,
    full_name,
    email,
    phone,
    country,
    customer_segment,
    registration_date,
    is_active,
    change_type,
    valid_from,
    COALESCE(valid_to_exclusive, STR_TO_DATE('9999-12-31 23:59:59', '%Y-%m-%d %H:%i:%s')) AS valid_to,
    CASE WHEN valid_to_exclusive IS NULL THEN TRUE ELSE FALSE END AS is_current,
    CASE
        WHEN change_type = 'deactivate' THEN 'Former Customer'
        WHEN is_active THEN 'Active'
        ELSE 'Inactive'
    END AS customer_status,
    batch_id,
    execution_date,
    ingestion_timestamp
FROM scd
