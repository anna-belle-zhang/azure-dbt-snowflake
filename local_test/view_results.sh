#!/bin/bash

# View Pipeline Results Script
# Query MySQL to see data in all layers

echo "===================================="
echo "PIPELINE RESULTS"
echo "===================================="
echo ""

MYSQL_CONTAINER=${LOCAL_MYSQL_CONTAINER:-$(docker ps --filter "name=mysql" --format "{{.ID}}" | head -n 1)}

if [ -z "$MYSQL_CONTAINER" ]; then
  echo "❌ Could not find a running MySQL container (name pattern *mysql*)."
  echo "Set LOCAL_MYSQL_CONTAINER=<container_name> and re-run."
  exit 1
fi

echo "📊 Bronze Layer (Raw Data)"
echo "------------------------"
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 bronze_db << 'SQL'
SELECT 'Customers' AS table_name, COUNT(*) AS row_count FROM bronze_customers
UNION ALL
SELECT 'Orders', COUNT(*) FROM bronze_orders;
SQL
echo ""

echo "🧹 Silver Layer (Cleaned Data)"
echo "------------------------"
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 silver_db << 'SQL'
SELECT 'Customers' AS table_name, COUNT(*) AS row_count FROM silver_customers
UNION ALL
SELECT 'Orders', COUNT(*) FROM silver_orders;

SELECT '---' AS separator;
SELECT 'Null emails in silver_customers:' AS info;
SELECT COUNT(*) AS null_emails FROM silver_customers WHERE email IS NULL;

SELECT '---' AS separator;
SELECT 'Negative order_amount rows remaining:' AS info;
SELECT COUNT(*) AS negative_orders FROM silver_orders WHERE order_amount < 0;
SQL
echo ""

echo "🏆 Gold Layer (Dimensional Model)"
echo "------------------------"
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 gold_db << 'SQL'
SELECT 'Customers' AS table_name, COUNT(*) AS row_count FROM dim_customers
UNION ALL
SELECT 'Orders', COUNT(*) FROM fct_orders;

SELECT '---' AS separator;
SELECT 'Top 5 Countries:' AS info;
SELECT country, COUNT(*) as customer_count
FROM dim_customers
GROUP BY country
ORDER BY customer_count DESC
LIMIT 5;
SQL
echo ""

echo "📈 Semantic Layer (Metrics)"
echo "------------------------"
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 semantic_db << 'SQL'
SELECT 'Top Revenue Segments:' AS info;
SELECT customer_segment, SUM(gross_revenue) AS revenue
FROM order_metrics
GROUP BY customer_segment
ORDER BY revenue DESC
LIMIT 5;

SELECT '---' AS separator;
SELECT 'Top Countries:' AS info;
SELECT country, SUM(gross_revenue) AS revenue
FROM order_metrics
GROUP BY country
ORDER BY revenue DESC
LIMIT 5;
SQL
echo ""

echo "===================================="
echo "RESULTS DISPLAYED ABOVE"
echo "===================================="
