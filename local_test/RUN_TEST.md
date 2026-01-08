# Local Integration Test - Quick Start Guide

## Prerequisites

- Docker running with MySQL (user: nocodb, password: nocodb123)
- Airflow running at http://localhost:8181 (admin/admin); port 8080 stays free for docs
- Python 3.9+ with `dbt-mysql` installed (dbt-utils comes from `dbt deps`). When running dbt manually, disable tracking to avoid the logbook bug by prefixing commands with `DBT_DISABLE_TRACKING=1` (e.g., `DBT_DISABLE_TRACKING=1 dbt docs generate --profiles-dir . --target dev`).

## Step 1: Setup Environment

Run the setup script:

```bash
cd /mnt/e/A/azure-dbt-snowflake
chmod +x local_test/setup_integration_test.sh
./local_test/setup_integration_test.sh
```

This will:
- Install Python dependencies
- Create MySQL databases (bronze_db, silver_db, gold_db, semantic_db)
- Copy files to Airflow container
- Install dependencies in Airflow

## Step 2: Generate & Encrypt Test Data

### Generate sample data:
```bash
python local_test/scripts/generate_data.py
```

This creates:
- `customers_<timestamp>.parquet` (1000 customers)
- `orders_<timestamp>.parquet` (5000 orders)

### Encrypt the files:
```bash
# Encrypt customers file
python local_test/scripts/encrypt_parquet.py customers_20240107_*.parquet

# Encrypt orders file
python local_test/scripts/encrypt_parquet.py orders_20240107_*.parquet
```

Files will be encrypted to `local_test/data/encrypted/`

## Step 3: Configure Airflow MySQL Connection

1. Open http://localhost:8181
2. Login: admin / admin
3. Go to **Admin → Connections**
4. Find or create `mysql_default`:
   - **Connection Type**: MySQL
   - **Host**: mysql
   - **Schema**: bronze_db
   - **Login**: nocodb
   - **Password**: nocodb123
   - **Port**: 3306
5. Click **Test** then **Save**

## Step 4: Run the Pipeline

1. Open http://localhost:8181 and go to **DAGs**
2. Find `local_encrypted_pipeline`
3. Click the toggle to **enable** it
4. Click **Trigger DAG** (play button)

### Pipeline Steps:
1. ✅ Detect encrypted file
2. ✅ Decrypt file (using Python script)
3. ✅ Create MySQL databases
4. ✅ Load to bronze layer
5. ✅ Run dbt (bronze → silver → gold → semantic)
6. ✅ Run dbt tests
7. ✅ Cleanup temporary files
8. ✅ Archive processed file

## Step 5: View Results

```bash
./local_test/view_results.sh
```

This shows row counts and sample data from:
- Bronze layer (raw data)
- Silver layer (cleaned data)
- Gold layer (dimensional model)
- Semantic layer (metrics)

### Manual MySQL Queries:

```bash
# Connect to MySQL (update the filter if your container name differs)
MYSQL_CONTAINER=$(docker ps --filter "name=mysql" --format "{{.ID}}" | head -n 1)
docker exec -it "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123

# View bronze data
USE bronze_db;
SELECT * FROM bronze_customers LIMIT 5;

# View gold data
USE gold_db;
SELECT * FROM dim_customers LIMIT 5;
SELECT * FROM fct_orders LIMIT 5;

# View semantic metrics
USE semantic_db;
SELECT * FROM order_metrics LIMIT 10;
```

## Step 6: Verify Security Controls

### Check encryption:
```bash
# Try to read encrypted file (should fail)
python -c "import pandas as pd; df = pd.read_parquet('local_test/data/encrypted/customers_20240107_120000.parquet.encrypted')"
# Expected: Error (file is encrypted)

# Decrypted files should be deleted
ls -la local_test/data/decrypted/
# Expected: Only metadata files, no .parquet files
```

### Check idempotency:
```bash
# Run pipeline twice with same file
# Should not create duplicates in silver/gold layers
```

### Check data quality:
```bash
# View quarantined records (if any)
MYSQL_CONTAINER=$(docker ps --filter "name=mysql" --format "{{.ID}}" | head -n 1)
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 silver_db << 'SQL'
SELECT * FROM silver_customers WHERE data_quality_flag IS NOT NULL LIMIT 10;
SQL
```

## Expected Results

### Data Volumes:
- **Bronze**: ~1000 customers, ~5000 orders
- **Silver**: ~990 customers (10 filtered), ~4950 orders (50 filtered)
- **Gold**: ~990 customers, ~4950 orders
- **Semantic**: ~990 customer metrics, ~365 daily revenue rows

### Data Quality Tests (dbt):
- ✅ Unique customer_id
- ✅ Not null constraints
- ✅ Foreign key relationships (orders → customers)
- ✅ No negative amounts

### Security:
- ✅ Encrypted files unreadable
- ✅ Decrypted files cleaned up (TTL)
- ✅ Keys stored separately (local_test/keys/)

## Troubleshooting

### Pipeline fails at "load_to_bronze"
**Issue**: MySQL connection error

**Fix**:
```bash
# Check MySQL is running
docker ps | grep mysql

# Test connection
MYSQL_CONTAINER=$(docker ps --filter "name=mysql" --format "{{.ID}}" | head -n 1)
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 -e "SHOW DATABASES;"
```

### dbt fails with "relation does not exist"
**Issue**: Source tables not created

**Fix**:
```bash
# Manually create source tables
MYSQL_CONTAINER=$(docker ps --filter "name=mysql" --format "{{.ID}}" | head -n 1)
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 bronze_db << 'SQL'
SHOW TABLES;
SQL

# Re-run load_to_bronze task in Airflow
```

### "No encrypted files found"
**Issue**: Files not in correct location

**Fix**:
```bash
# Check files
ls -la local_test/data/encrypted/

# Encrypt files if missing
python local_test/scripts/generate_data.py
python local_test/scripts/encrypt_parquet.py customers_*.parquet
```

## Clean Up

```bash
# Drop databases
MYSQL_CONTAINER=$(docker ps --filter "name=mysql" --format "{{.ID}}" | head -n 1)
docker exec -i "${MYSQL_CONTAINER}" mysql -unocodb -pnocodb123 << 'SQL'
DROP DATABASE IF EXISTS bronze_db;
DROP DATABASE IF EXISTS silver_db;
DROP DATABASE IF EXISTS gold_db;
DROP DATABASE IF EXISTS semantic_db;
SQL

# Remove test data
rm -rf local_test/data/encrypted/*
rm -rf local_test/data/decrypted/*
rm -rf local_test/data/archive/*
rm -rf local_test/keys/*
```

## Next Steps

After successful local testing:
1. ✅ Validate encryption/decryption works
2. ✅ Validate dbt transformations (bronze → silver → gold → semantic)
3. ✅ Validate data quality tests pass
4. ⏭️ Migrate to Azure (Blob Storage, Key Vault, Azure Function)
5. ⏭️ Migrate to Snowflake (replace MySQL)
6. ⏭️ Implement full RBAC (Snowflake roles, masking policies)

---

**Test Duration**: ~10 minutes (setup + run + validate)
**Success Criteria**: All DAG tasks green ✅, data in all 4 layers
