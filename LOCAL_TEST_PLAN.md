# Local Test Plan - Data Pipeline Architecture

## Overview

This plan creates a local testing environment that simulates the production architecture using:
- **MySQL** (instead of Snowflake)
- **Local file system** (instead of Azure Blob Storage)
- **Python encryption** (instead of Azure Key Vault)
- **Airflow** (Docker - existing)
- **dbt-mysql** (instead of dbt-snowflake)

## Architecture Mapping

| Production | Local Test |
|------------|------------|
| Azure Blob Storage | `./data/encrypted/` directory |
| Azure Key Vault | Local key file `./keys/encryption.key` |
| Azure Function | Python script `scripts/decrypt_parquet.py` |
| Snowflake | MySQL (Docker) |
| dbt-snowflake | dbt-mysql |
| Airflow (AKS) | Airflow (Docker - existing) |

## Directory Structure

```
azure-dbt-snowflake/
├── local_test/
│   ├── data/
│   │   ├── encrypted/          # Simulates Azure Blob encrypted landing
│   │   ├── decrypted/          # Simulates temporary decrypted staging
│   │   └── archive/            # Processed files
│   ├── keys/
│   │   └── encryption.key      # Simulates Azure Key Vault
│   ├── scripts/
│   │   ├── generate_data.py    # Generate sample customer data
│   │   ├── encrypt_parquet.py  # Encrypt Parquet files
│   │   └── decrypt_parquet.py  # Decrypt Parquet files
│   ├── dbt_local/
│   │   ├── models/
│   │   │   ├── bronze/         # Raw data models
│   │   │   ├── silver/         # Cleaned data models
│   │   │   ├── gold/           # Dimensional models
│   │   │   └── semantic/       # Metrics/aggregations
│   │   ├── tests/              # Data quality tests
│   │   ├── macros/             # Reusable macros
│   │   ├── dbt_project.yml
│   │   └── profiles.yml
│   ├── airflow/
│   │   └── dags/
│   │       └── local_encrypted_pipeline.py
│   └── docker/
│       └── docker-compose.yml  # MySQL + Airflow setup
└── requirements_local.txt
```

## Components

### 1. Data Generation & Encryption (Python)

**generate_data.py**: Creates sample customer/order data as Parquet
**encrypt_parquet.py**: Encrypts Parquet using Fernet (symmetric encryption)
**decrypt_parquet.py**: Decrypts Parquet files

### 2. MySQL Database Setup

**Databases**:
- `bronze_db` - Raw data (immutable)
- `silver_db` - Cleaned data
- `gold_db` - Dimensional models
- `semantic_db` - Metrics views

### 3. dbt Project (dbt-mysql)

**Models**:
- **Bronze**: Load raw JSON/Parquet data
- **Silver**: Clean, deduplicate, type-cast
- **Gold**: Dimensional models (facts, dimensions)
- **Semantic**: Business metrics

### 4. Airflow DAG

**Pipeline**:
1. Detect encrypted file in `./data/encrypted/`
2. Decrypt using Python script
3. Load to MySQL bronze layer
4. Run dbt transformations (bronze → silver → gold → semantic)
5. Run data quality tests
6. Archive processed file

## Test Scenarios

### Scenario 1: Happy Path
1. Generate sample data (1000 customers, 5000 orders)
2. Encrypt Parquet file
3. Trigger Airflow DAG
4. Verify data in all layers (bronze → silver → gold → semantic)
5. Check data quality tests pass

### Scenario 2: Duplicate File Handling (Idempotency)
1. Process same file twice
2. Verify no duplicate records in silver/gold layers
3. Check `batch_id` tracking works

### Scenario 3: Data Quality Failure
1. Generate data with missing customer_ids
2. Process file
3. Verify records quarantined
4. Check DAG handles failure gracefully

### Scenario 4: Late-Arriving Data
1. Load data for 2024-01-01
2. Load data for 2024-01-03
3. Load late data for 2024-01-02
4. Verify correct event_time handling

### Scenario 5: Schema Change
1. Load data with original schema
2. Add new column to source data
3. Verify dbt `on_schema_change` behavior

## Success Criteria

### ✅ Data Integrity
- [ ] All records from source appear in bronze layer
- [ ] No duplicate records in silver/gold layers
- [ ] Foreign key relationships maintained (customer → orders)

### ✅ Transformation Logic
- [ ] Silver layer: NULL values handled, types correct
- [ ] Gold layer: Aggregations correct, dimensions populated
- [ ] Semantic layer: Metrics calculate correctly

### ✅ Security & Compliance
- [ ] Encrypted files cannot be read without key
- [ ] Decrypted files are temporary (cleaned up after load)
- [ ] `batch_id` tracking enables reproducibility

### ✅ Operational Resilience
- [ ] Failed files move to quarantine
- [ ] Airflow retries work as expected
- [ ] dbt tests catch data quality issues

### ✅ Monitoring
- [ ] Airflow DAG success/failure logged
- [ ] dbt test results captured
- [ ] Row counts validated at each layer

## Performance Targets (Local)

| Metric | Target |
|--------|--------|
| File encryption | < 5 seconds (1000 rows) |
| File decryption | < 5 seconds (1000 rows) |
| MySQL load (bronze) | < 10 seconds (1000 rows) |
| dbt run (all layers) | < 30 seconds |
| End-to-end pipeline | < 2 minutes |

## Limitations vs Production

| Feature | Production | Local Test | Reason |
|---------|-----------|------------|--------|
| Encryption | Azure Key Vault | Local file | Simpler for testing |
| Storage | Azure Blob (geo-redundant) | Local filesystem | No cloud dependency |
| Database | Snowflake (columnar) | MySQL (row-based) | Performance differs |
| Compute | Separate warehouses | Single MySQL instance | Resource constraints |
| Monitoring | Azure Monitor + Snowflake | Airflow logs | Simplified observability |
| RBAC | Full Snowflake RBAC | MySQL users | Simpler permissions |

## Next Steps After Local Testing

1. ✅ **Validate core logic** - Encryption, transformations, data quality
2. ✅ **Test failure scenarios** - Quarantine, retries, schema changes
3. ⏭️ **Migrate to Azure** - Replace local components with Azure services
4. ⏭️ **Migrate to Snowflake** - Replace MySQL with Snowflake
5. ⏭️ **Implement full RBAC** - Snowflake roles, masking policies
6. ⏭️ **Add monitoring** - Azure Monitor, Snowflake query history

## Running the Test

See `LOCAL_TEST_SETUP.md` for detailed setup and execution instructions.

---

**Purpose**: Local validation of architecture before cloud deployment
**Duration**: ~2 hours (setup + testing)
**Dependencies**: Docker, Python 3.9+, MySQL, Airflow
