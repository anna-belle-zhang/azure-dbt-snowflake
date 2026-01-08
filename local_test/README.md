# Local Integration Test Environment

This directory contains a complete local testing environment that simulates the production architecture using Docker containers.

## Architecture Overview

```
┌─────────────────┐      ┌──────────────┐      ┌─────────────┐
│ Generate Data   │ ───▶ │  Encrypt     │ ───▶ │  Airflow    │
│ (Python)        │      │  (Fernet)    │      │  DAG        │
└─────────────────┘      └──────────────┘      └──────┬──────┘
                                                       │
                                                       ▼
                         ┌──────────────┐      ┌──────────────┐
                         │  Decrypt     │ ───▶ │  MySQL       │
                         │  (Python)    │      │  Bronze      │
                         └──────────────┘      └──────┬───────┘
                                                       │
                                                       ▼
                         ┌──────────────────────────────────┐
                         │         dbt Pipeline             │
                         │  Bronze → Silver → Gold → Semantic│
                         └──────────────────────────────────┘
```

## Directory Structure

```
local_test/
├── data/
│   ├── encrypted/      # Landing zone for encrypted Parquet
│   ├── decrypted/      # Temporary staging (TTL simulation)
│   └── archive/        # Processed files
├── keys/
│   └── encryption.key  # Fernet encryption key (simulates Key Vault)
├── scripts/
│   ├── generate_data.py    # Generate sample customer/order data
│   ├── encrypt_parquet.py  # Encrypt Parquet files
│   └── decrypt_parquet.py  # Decrypt Parquet files
├── dbt_local/
│   ├── models/
│   │   ├── bronze/     # Raw data models
│   │   ├── silver/     # Cleaned data models
│   │   ├── gold/       # Dimensional models (facts/dims)
│   │   └── semantic/   # Metrics and aggregations
│   ├── dbt_project.yml
│   └── profiles.yml
├── airflow/
│   └── dags/
│       └── local_encrypted_pipeline.py  # Main pipeline DAG
├── setup_integration_test.sh  # Setup script
├── view_results.sh            # View pipeline results
├── RUN_TEST.md               # Step-by-step test guide
└── requirements.txt          # Python dependencies
```

## Quick Start

### 1. Prerequisites

- Docker with MySQL running (user: nocodb, password: nocodb123)
- Airflow UI exposed at http://localhost:8181 (admin/admin) so port 8080 can stay dedicated to docs
- Python 3.9+
- dbt CLI installed with the `dbt-mysql` adapter (dbt-utils comes from `dbt deps`); export `DBT_DISABLE_TRACKING=1` whenever you run dbt locally to avoid the logbook buffer error

### 2. Install Local Requirements

```bash
pip install -r local_test/requirements.txt  # includes logbook<1.7 for dbt compatibility
```

### 3. Run Setup

```bash
./local_test/setup_integration_test.sh
```

### 4. Generate & Encrypt Data

```bash
# Generate sample data
python local_test/scripts/generate_data.py

# Encrypt files
python local_test/scripts/encrypt_parquet.py customers_*.parquet
python local_test/scripts/encrypt_parquet.py orders_*.parquet
```

### 5. Run Pipeline

1. Open http://localhost:8181
2. Enable and trigger `local_encrypted_pipeline` DAG
3. (If running dbt manually) execute `dbt deps` inside `local_test/dbt_local` so packages like `dbt-utils` install before `dbt run`/`dbt docs`

> **Tip:** If you run dbt commands outside of Airflow (e.g., `dbt build`, `dbt docs generate`), prefix them with `DBT_DISABLE_TRACKING=1` to bypass the known logbook emitter bug:  
> `DBT_DISABLE_TRACKING=1 dbt docs generate --profiles-dir . --target dev`

### 6. View Results

```bash
./local_test/view_results.sh
```

## What Gets Tested

### ✅ Security Controls
- Encryption/decryption (Fernet symmetric encryption)
- File hash validation (idempotency)
- Temporary file cleanup (TTL simulation)
- Key management (separate key file)

### ✅ Data Pipeline
- **Bronze layer**: Raw data, immutable, append-only
- **Silver layer**: Cleaned, deduplicated, validated
- **Gold layer**: Dimensional model (facts + dimensions)
- **Semantic layer**: Business metrics

### ✅ Data Quality
- Not null constraints
- Unique keys
- Foreign key relationships
- Data type validation
- Business rule checks (e.g., no negative amounts)

### ✅ Operational Concerns
- Batch tracking (batch_id, execution_date)
- Data quality flags
- Error quarantine
- Airflow retries
- dbt tests

## Test Scenarios

See `LOCAL_TEST_PLAN.md` for detailed test scenarios:
1. Happy path
2. Duplicate file handling (idempotency)
3. Data quality failures
4. Late-arriving data
5. Schema changes

## Limitations vs Production

| Feature | Production | Local Test |
|---------|-----------|------------|
| Encryption | Azure Key Vault | Local Fernet key file |
| Storage | Azure Blob Storage | Local filesystem |
| Database | Snowflake | MySQL |
| Compute | Separate warehouses | Single MySQL instance |
| RBAC | Full Snowflake RBAC | Basic MySQL permissions |

## Files Reference

| File | Purpose |
|------|---------|
| `RUN_TEST.md` | **START HERE** - Step-by-step guide |
| `LOCAL_TEST_PLAN.md` | Comprehensive test plan |
| `setup_integration_test.sh` | Automated setup |
| `view_results.sh` | Query results |
| `requirements.txt` | Python dependencies |

## Support

For detailed instructions, see `RUN_TEST.md`.

For test scenarios and success criteria, see `LOCAL_TEST_PLAN.md`.

---

**Created**: 2026-01-07
**Purpose**: Local validation before Azure/Snowflake deployment
**Duration**: ~10 minutes (setup + test)
