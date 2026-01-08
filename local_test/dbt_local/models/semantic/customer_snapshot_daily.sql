{{
  config(
    materialized='view',
    tags=['semantic', 'customer_snapshot']
  )
}}

-- Daily customer snapshot derived from the SCD2 dimension.
-- Captures how many customers were inserted, updated, or deactivated per day
-- and produces a running active count estimate (inserts - deactivations).

WITH scd_events AS (
    SELECT
        COALESCE(DATE(valid_from), CURRENT_DATE()) AS event_date,
        change_type
    FROM {{ ref('dim_customers_scd2') }}
),

daily_events AS (
    SELECT
        event_date,
        SUM(CASE WHEN change_type = 'insert' THEN 1 ELSE 0 END) AS customers_inserted,
        SUM(CASE WHEN change_type = 'update' THEN 1 ELSE 0 END) AS customers_updated,
        SUM(CASE WHEN change_type = 'deactivate' THEN 1 ELSE 0 END) AS customers_deactivated
    FROM scd_events
    GROUP BY event_date
),

with_net_change AS (
    SELECT
        event_date,
        customers_inserted,
        customers_updated,
        customers_deactivated,
        customers_inserted - customers_deactivated AS net_active_change
    FROM daily_events
),

running_totals AS (
    SELECT
        event_date,
        customers_inserted,
        customers_updated,
        customers_deactivated,
        net_active_change,
        SUM(net_active_change) OVER (
            ORDER BY event_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS active_customers_estimate
    FROM with_net_change
)

SELECT
    event_date,
    customers_inserted,
    customers_updated,
    customers_deactivated,
    net_active_change,
    active_customers_estimate
FROM running_totals
ORDER BY event_date
