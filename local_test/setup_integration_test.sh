#!/bin/bash

# Integration Test Setup Script
# This script sets up the local environment for testing the data pipeline

set -e  # Exit on error

echo "===================================="
echo "LOCAL PIPELINE INTEGRATION TEST SETUP"
echo "===================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required"
    exit 1
fi

echo "✅ Prerequisites met"
echo ""

# Install Python dependencies
echo "Installing Python dependencies..."
pip install -r local_test/requirements.txt -q
echo "✅ Python packages installed"
echo ""

# Create directory structure
echo "Creating directory structure..."
mkdir -p local_test/data/{encrypted,decrypted,archive}
mkdir -p local_test/keys
echo "✅ Directories created"
echo ""

# Setup MySQL databases
echo "Setting up MySQL databases..."
MYSQL_CONTAINER=${LOCAL_MYSQL_CONTAINER:-$(docker ps --filter "name=mysql" --format "{{.ID}}" | head -n 1)}
if [ -z "$MYSQL_CONTAINER" ]; then
    echo "❌ Could not find a running MySQL container (name pattern '*mysql*')."
    echo "   Set LOCAL_MYSQL_CONTAINER=<container_name> and rerun."
    exit 1
fi
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 << 'SQL'
CREATE DATABASE IF NOT EXISTS bronze_db;
CREATE DATABASE IF NOT EXISTS silver_db;
CREATE DATABASE IF NOT EXISTS gold_db;
CREATE DATABASE IF NOT EXISTS semantic_db;
SHOW DATABASES;
SQL
echo "✅ MySQL databases created"
echo ""

# Copy Airflow DAG
echo "Copying Airflow DAG to Airflow container..."
AIRFLOW_CONTAINER=${LOCAL_AIRFLOW_CONTAINER:-$(docker ps --filter "name=airflow" --format "{{.Names}}" | head -n 1)}

if [ -z "$AIRFLOW_CONTAINER" ]; then
    AIRFLOW_CONTAINER=$(docker ps --filter "name=openmetadata_ingestion" --format "{{.Names}}" | head -n 1)
fi

if [ -z "$AIRFLOW_CONTAINER" ]; then
    echo "❌ Airflow container not found. Set LOCAL_AIRFLOW_CONTAINER=<container_name> and rerun."
    exit 1
fi

# Copy entire local_test directory to Airflow container
docker cp local_test ${AIRFLOW_CONTAINER}:/opt/airflow/
docker cp local_test/airflow/dags/local_encrypted_pipeline.py ${AIRFLOW_CONTAINER}:/opt/airflow/dags/

echo "✅ Files copied to Airflow container"
echo ""

# Install dependencies in Airflow container
echo "Installing dependencies in Airflow container..."
docker exec ${AIRFLOW_CONTAINER} pip install pandas pyarrow cryptography sqlalchemy pymysql dbt-mysql dbt-utils --quiet
echo "✅ Dependencies installed in Airflow"
echo ""

echo "===================================="
echo "SETUP COMPLETE!"
echo "===================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Generate test data:"
echo "   ${GREEN}python local_test/scripts/generate_data.py${NC}"
echo ""
echo "2. Encrypt the data:"
echo "   ${GREEN}python local_test/scripts/encrypt_parquet.py customers_*.parquet${NC}"
echo "   ${GREEN}python local_test/scripts/encrypt_parquet.py orders_*.parquet${NC}"
echo ""
echo "3. Trigger Airflow DAG:"
echo "   ${GREEN}Open http://localhost:8181 (admin/admin)${NC}"
echo "   ${YELLOW}Enable and trigger: 'local_encrypted_pipeline'${NC}"
echo ""
echo "4. View results:"
echo "   ${GREEN}./local_test/view_results.sh${NC}"
echo ""
