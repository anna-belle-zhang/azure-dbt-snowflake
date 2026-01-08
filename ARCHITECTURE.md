# Data Pipeline Architecture - Encrypted Parquet to Snowflake

> **Regulatory Compliance First**: This architecture embeds APRA CPS 230/234/235, Privacy Act, and ASIC requirements directly into the data lifecycle, not as bolt-ons.

## Executive Summary

**This architecture passes audit because it transforms "engineering certainty" into "regulatory certainty".**

The design addresses the 6 core questions that Australian financial regulators and auditors ask:
1. **Data Exposure**: Is sensitive data unnecessarily exposed?
2. **Access Traceability**: Who accessed what data, when?
3. **Data Integrity**: Has data been tampered with or silently corrupted?
4. **Incident Response**: Can issues be quickly located and contained?
5. **Reproducibility**: Can historical results be recalculated and explained?
6. **Key Management**: Are keys and permissions centrally controlled and auditable?

**Core Principle**: Encryption, access control, lineage, and reproducibility are not add-ons—they are default behaviors of the platform.

---

## Regulatory Compliance Framework

### Australian Financial Services Regulations Addressed

| Regulation | Requirement | How Architecture Complies |
|------------|-------------|---------------------------|
| **APRA CPS 234** | Information asset protection, encryption, access control | Client-side encryption + Key Vault; RBAC with masking; access history logging |
| **APRA CPS 230** | Operational risk management, incident response | Airflow DAG runs with SLA monitoring; failure callbacks; quarantine tables |
| **APRA CPS 235** | Data risk management, data quality | dbt tests as system-enforced quality; versioned transformations; lineage tracking |
| **Privacy Act 1988** | Minimal data exposure, consent-based access | PII masking by default; least privilege RBAC; limited plaintext TTL |
| **ASIC Reporting** | Data explainability, audit trails | batch_id + rule_version; reproducible calculations; dbt documentation |

### Six Audit Questions & Architecture Responses

#### 1. "When and where does plaintext data exist?"

**Auditor's Concern**: Minimizing attack surface for sensitive data

**Architecture Response**:
- **Encrypted at source**: Files exist only as ciphertext in Azure Blob Storage
- **Controlled decryption**: Occurs only in secure compute boundary (Azure Function with managed identity)
- **Short-lived plaintext**: Decrypted files have TTL and are not persisted long-term
- **No code/DAG exposure**: Keys never appear in code, Airflow variables, or logs (Key Vault only)
- **Tagged with run_id/batch_id**: Every decryption operation is traceable

**Compliance**: Privacy Act (minimal exposure) + CPS 234 (asset protection)

#### 2. "Why is Airflow + dbt audit-friendly?"

**Auditor's Concern**: Business timeline and responsibility boundaries must be clear

**Architecture Response**:

**Airflow (Operational Accountability)**:
- Every ingestion = one DAG run with:
  - `execution_date` (business time)
  - `retry` count and delays
  - `failure_callback` with alerting
  - `SLA` monitoring
- System failures are visible, alertable, and explainable
- Maps to **APRA CPS 230** (Operational Risk)

**dbt (Business Logic as Audit Asset)**:
- Auditors trust: Git version control, documentation, automated tests
- Auditors distrust: Notebooks, ad-hoc SQL, manual processes
- dbt provides:
  - Versioned business rules (Git history)
  - Model lineage (visual DAG)
  - Field-level definitions (schema.yml)
  - Data quality tests (system-enforced)
- Maps to **APRA CPS 235** (data accuracy = system guarantee, not human guarantee)

#### 3. "How do you prevent data tampering?"

**Auditor's Concern**: Original data integrity and change tracking

**Architecture Response**:

**Layered Immutability**:
- **Bronze (RAW)**: Immutable, append-only, never updated
- **Silver**: Cleaned/standardized but traceable to Bronze
- **Gold**: "Source of Truth" for external consumption
- **Semantic**: Metrics layer, never writes back to history

**Recovery Capability**:
- Issues can be resolved by:
  - Returning to upstream layer
  - Recalculating downstream layers
  - Comparing differences with `batch_id` tracking
- Original facts are permanently preserved

**Compliance**: Auditors conclude "data evolution path is clear, irreversible operations are controlled"

#### 4. "How do you enforce 'least privilege'?"

**Auditor's Concern**: "We trust analysts not to misuse data" ≠ audit-compliant

**Architecture Response**:

**Snowflake RBAC + Policies** (see section 3.3 for details):
- **Separation of duties**: Engineering / Analytics / BI roles isolated
- **Masking by default**: PII fields automatically redacted unless user has specific role
- **Row-level security**: Business unit data isolation via policies
- **Access history**: `QUERY_HISTORY` and `ACCESS_HISTORY` tables capture all access

**System-Enforced, Not Human-Enforced**:
- Not relying on "user awareness"
- Compliance is platform default behavior

**Compliance**: Privacy Act (access minimization) + CPS 234 (access control & audit)

#### 5. "Can you explain this number from 12 months ago?"

**Auditor's Concern**: Reproducibility and calculation transparency

**Architecture Response**:

Every calculation is traceable via:
- **Original file**: `file_hash` in metadata
- **Batch run**: `batch_id` from Airflow execution
- **Business rules**: `dbt` model version (Git commit SHA)
- **Time context**: `execution_date` and `event_time` vs `process_time`

**Reproducibility Pattern**:
```sql
-- Example: Reproduce calculation
SELECT *
FROM gold.fact_orders
WHERE batch_id = '<specific_airflow_run>'
  AND dbt_model_version = '<git_sha>'
  AND execution_date = '2024-01-06';
```

**Compliance**: ASIC reporting explainability + APRA data reproducibility

#### 6. "What if business logic changes?"

**Auditor's Concern**: Same data, different results by different people

**Architecture Response**:

**Gold Layer (Versioned Truth)**:
- Changes data granularity
- Consolidates facts
- Solidifies rules (versioned via dbt + Git)

**Semantic Layer (Reusable Metrics)**:
- Only explainable, reusable metrics
- Never alters historical facts
- Dynamic calculations scoped to recent windows only (see section 2.5)

**Result**:
- Historical reports remain stable
- Dynamic analysis has clear boundaries
- Rule changes are auditable via Git

**Compliance**: Consistent calculation = regulatory trust

---

## 1. End-to-End Pipeline Architecture

### 1.1 High-Level Overview

```
Azure Blob Storage (Encrypted Parquet)
          ↓
    Airflow File Watcher
          ↓
Azure Function (Decrypt & Stage)
          ↓
    Snowflake Stage (External)
          ↓
    dbt Transformations
          ↓
Snowflake (Bronze → Silver → Gold → Semantic)
          ↓
      BI Layer
```

### 1.2 Components and Integration

#### **Stage 1: Data Ingestion (Azure Blob Storage)**
- **Service**: Azure Blob Storage with encryption at rest
- **Input**: Encrypted Parquet files (customer data)
- **Container**: `raw-encrypted-data`
- **Encryption**: Azure Storage Service Encryption (SSE) + client-side encryption
- **Naming Convention**: `<source>/<date>/data_<timestamp>.parquet.encrypted`

#### **Stage 2: Orchestration Detection (Airflow)**
- **Service**: Azure Container Instances running Airflow or Astronomer Cloud
- **Component**: File Watcher Operator (Azure Blob Sensor)
- **DAG Structure**:
  ```python
  # airflow/dags/encrypted_parquet_pipeline.py

  detect_file → decrypt_and_stage → snowflake_copy_into → dbt_run_bronze →
  dbt_run_silver → dbt_run_gold → dbt_run_semantic → data_quality_check →
  notify_completion
  ```

#### **Stage 3: Decryption Layer (Azure Function)**
- **Service**: Azure Functions (Python) with managed identity
- **Purpose**:
  - Decrypt Parquet files using Azure Key Vault keys
  - Validate file integrity (checksum)
  - Stage decrypted files to intermediate blob container
- **Key Management**: Azure Key Vault with customer-managed keys (CMK)
- **Output**: Decrypted Parquet in `staged-decrypted-data` container

**Function Flow**:
```python
1. Triggered by Airflow HTTP request
2. Retrieve decryption key from Key Vault via managed identity
3. Download encrypted file from blob storage
4. Decrypt file chunks in memory (streaming)
5. Validate schema and data quality
6. Upload to staging container
7. Return metadata (row count, file size, schema hash)
```

#### **Stage 4: Snowflake External Stage**
- **Service**: Snowflake External Stage pointing to Azure Blob
- **Integration**: Azure Storage Integration with managed identity
- **DDL**:
  ```sql
  CREATE STORAGE INTEGRATION azure_blob_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'AZURE'
    ENABLED = TRUE
    AZURE_TENANT_ID = '<tenant_id>'
    STORAGE_ALLOWED_LOCATIONS = ('azure://stagedstorage.blob.core.windows.net/staged-decrypted-data/');

  CREATE STAGE bronze_stage
    STORAGE_INTEGRATION = azure_blob_integration
    URL = 'azure://stagedstorage.blob.core.windows.net/staged-decrypted-data/'
    FILE_FORMAT = (TYPE = PARQUET);
  ```

#### **Stage 5: Data Loading (Snowflake COPY INTO)**
- **Method**: COPY INTO command orchestrated by Airflow
- **Target**: Bronze layer (raw data schema)
- **Pattern**:
  ```sql
  COPY INTO bronze.raw_customer_data
  FROM @bronze_stage/customer/2024-01-06/
  FILE_FORMAT = (TYPE = PARQUET)
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = 'SKIP_FILE'
  RETURN_FAILED_ONLY = TRUE;
  ```

#### **Stage 6: dbt Transformations**
- **Service**: dbt Core running in Docker container (ACI or Airflow KubernetesPodOperator)
- **Orchestration**: Triggered by Airflow after successful COPY INTO
- **Profile**: Snowflake connector with key-pair authentication

**dbt Project Structure**:
```
dbt_project/
├── models/
│   ├── bronze/         # Raw data, 1:1 with source
│   ├── silver/         # Cleaned, deduplicated, type-cast
│   ├── gold/           # Business logic, dimensional models
│   └── semantic/       # Metrics, aggregations, business definitions
├── macros/
│   └── decrypt_pii.sql # PII decryption macro (if needed)
├── tests/
│   └── data_quality/   # Custom data quality tests
└── snapshots/          # SCD Type 2 tracking
```

#### **Stage 7: BI Layer**
- **Tools**: Power BI, Tableau, or Looker
- **Connection**: Direct query to Snowflake semantic layer
- **Security**: Row-level security (RLS) via Snowflake roles

---

## 2. Lakehouse Architecture & Dimensional Modelling

### 2.1 Real-World Pipeline: JSON Logs to Dimensional Model

**Use Case**: E-commerce clickstream logs

**Bronze Layer (Raw Data)**:
```sql
-- bronze.raw_clickstream_events
-- Ingested as-is from source
CREATE TABLE bronze.raw_clickstream_events (
  event_payload VARIANT,          -- Raw JSON
  event_timestamp TIMESTAMP_NTZ,
  file_name STRING,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Load from stage
COPY INTO bronze.raw_clickstream_events
FROM @bronze_stage/clickstream/
FILE_FORMAT = (TYPE = JSON);
```

**Silver Layer (Cleaned & Normalized)**:
```sql
-- silver.clickstream_events
-- Flatten JSON, type casting, deduplication
CREATE TABLE silver.clickstream_events AS
SELECT
  event_payload:event_id::STRING AS event_id,
  event_payload:user_id::STRING AS user_id,
  event_payload:session_id::STRING AS session_id,
  event_payload:event_type::STRING AS event_type,
  event_payload:page_url::STRING AS page_url,
  event_payload:product_id::STRING AS product_id,
  TRY_CAST(event_payload:revenue::STRING AS DECIMAL(10,2)) AS revenue,
  event_payload:timestamp::TIMESTAMP_NTZ AS event_timestamp,
  event_payload:user_agent::STRING AS user_agent,
  event_payload:ip_address::STRING AS ip_address,
  -- Derived fields
  DATE(event_timestamp) AS event_date,
  -- Data quality flags
  CASE
    WHEN event_id IS NULL THEN 'missing_event_id'
    WHEN user_id IS NULL THEN 'missing_user_id'
    ELSE NULL
  END AS data_quality_flag,
  -- Metadata
  ingestion_timestamp,
  CURRENT_TIMESTAMP() AS transformation_timestamp
FROM bronze.raw_clickstream_events
QUALIFY ROW_NUMBER() OVER (PARTITION BY event_payload:event_id ORDER BY ingestion_timestamp DESC) = 1;
```

**Gold Layer (Dimensional Model)**:
```sql
-- gold.dim_users (SCD Type 2)
CREATE TABLE gold.dim_users (
  user_key INT IDENTITY PRIMARY KEY,
  user_id STRING,
  user_name STRING,
  user_email STRING,
  user_segment STRING,
  country STRING,
  -- SCD Type 2 columns
  effective_from TIMESTAMP_NTZ,
  effective_to TIMESTAMP_NTZ,
  is_current BOOLEAN,
  -- Metadata
  created_at TIMESTAMP_NTZ,
  updated_at TIMESTAMP_NTZ
);

-- gold.dim_products
CREATE TABLE gold.dim_products (
  product_key INT IDENTITY PRIMARY KEY,
  product_id STRING,
  product_name STRING,
  product_category STRING,
  product_subcategory STRING,
  brand STRING,
  price DECIMAL(10,2),
  is_active BOOLEAN,
  created_at TIMESTAMP_NTZ,
  updated_at TIMESTAMP_NTZ
);

-- gold.dim_date
CREATE TABLE gold.dim_date (
  date_key INT PRIMARY KEY,
  date_value DATE,
  year INT,
  quarter INT,
  month INT,
  week INT,
  day_of_week INT,
  day_name STRING,
  is_weekend BOOLEAN,
  is_holiday BOOLEAN,
  fiscal_year INT,
  fiscal_quarter INT
);

-- gold.fact_clickstream_events
CREATE TABLE gold.fact_clickstream_events (
  event_key INT IDENTITY PRIMARY KEY,
  event_id STRING,
  user_key INT REFERENCES gold.dim_users(user_key),
  product_key INT REFERENCES gold.dim_products(product_key),
  date_key INT REFERENCES gold.dim_date(date_key),
  session_id STRING,
  event_type STRING,
  page_url STRING,
  revenue DECIMAL(10,2),
  event_timestamp TIMESTAMP_NTZ,
  -- Aggregated metrics
  session_duration_seconds INT,
  page_views_in_session INT,
  -- Metadata
  created_at TIMESTAMP_NTZ
);
```

**Semantic Layer (Metrics & Business Logic)**:
```sql
-- semantic.user_engagement_metrics
CREATE VIEW semantic.user_engagement_metrics AS
SELECT
  u.user_id,
  u.user_segment,
  d.date_value,
  COUNT(DISTINCT f.session_id) AS sessions,
  COUNT(f.event_id) AS total_events,
  SUM(CASE WHEN f.event_type = 'page_view' THEN 1 ELSE 0 END) AS page_views,
  SUM(CASE WHEN f.event_type = 'purchase' THEN 1 ELSE 0 END) AS purchases,
  SUM(f.revenue) AS total_revenue,
  AVG(f.session_duration_seconds) AS avg_session_duration,
  -- Calculated metrics
  NULLIF(SUM(CASE WHEN f.event_type = 'purchase' THEN 1 ELSE 0 END), 0) /
    NULLIF(COUNT(DISTINCT f.session_id), 0) AS conversion_rate
FROM gold.fact_clickstream_events f
JOIN gold.dim_users u ON f.user_key = u.user_key
JOIN gold.dim_date d ON f.date_key = d.date_key
WHERE u.is_current = TRUE
GROUP BY 1, 2, 3;
```

### 2.2 Lakehouse vs Cloud Data Warehouse

| Aspect | Lakehouse (e.g., Databricks, Snowflake with Iceberg) | Cloud Data Warehouse (e.g., Snowflake, BigQuery) |
|--------|------------------------------------------------------|--------------------------------------------------|
| **Storage Format** | Open formats (Parquet, Delta, Iceberg) on object storage | Proprietary columnar format |
| **Schema Enforcement** | Schema-on-read and schema-on-write | Schema-on-write (strict) |
| **Data Types** | Structured, semi-structured, unstructured | Primarily structured, some semi-structured |
| **ACID Transactions** | Yes (with Delta Lake, Iceberg) | Yes (native) |
| **Query Engine** | Multiple engines (Spark, Presto, dbt) | Single proprietary engine (optimized) |
| **Cost Model** | Storage + compute separately | Storage + compute (with some separation) |
| **Use Cases** | ML, data science, ELT, streaming | BI, analytics, reporting |

**Key Difference**: Lakehouse decouples storage from compute completely and supports open formats, enabling multiple tools to access the same data. Data warehouses optimize for query performance with proprietary formats.

### 2.3 Medallion Architecture + Dimensional Modelling

**Complementary Aspects**:
- **Medallion Architecture**: Data quality progression (Bronze → Silver → Gold)
- **Dimensional Modelling**: Query optimization via denormalization (facts & dimensions)

**Integration**:
- **Bronze**: Raw data (no dimensional modeling)
- **Silver**: Normalized tables, business keys exposed
- **Gold**: Dimensional models (star/snowflake schemas)
- **Semantic**: Pre-aggregated metrics, business KPIs

**Overlap**:
- Both promote data quality and governance
- Both create layers of abstraction
- Gold layer implements dimensional models
- Semantic layer may use conformed dimensions from Gold

### 2.4 Business Logic Distribution: Gold vs Semantic

**Architecture**: Bronze → Silver → Gold → Semantic → BI Layer

#### **Must Stay in Gold Layer**:
1. **Dimensional Modeling** (facts, dimensions, SCD Type 2)
2. **Referential Integrity** (foreign keys, surrogate keys)
3. **Data Quality Rules** (validation, cleansing)
4. **Historical Tracking** (snapshots, slowly changing dimensions)
5. **Complex Joins** (denormalization for performance)

**Why**: These are foundational data structures that multiple semantic models will reference. They ensure data consistency and reusability.

**Example**:
```sql
-- gold.fact_orders (MUST be in Gold)
CREATE TABLE gold.fact_orders AS
SELECT
  o.order_key,
  u.user_key,
  p.product_key,
  d.date_key,
  o.quantity,
  o.unit_price,
  o.quantity * o.unit_price AS total_amount
FROM silver.orders o
JOIN gold.dim_users u ON o.user_id = u.user_id
JOIN gold.dim_products p ON o.product_id = p.product_id
JOIN gold.dim_date d ON o.order_date = d.date_value;
```

#### **Must Move to Semantic Layer**:
1. **Business Metrics** (KPIs, calculated measures)
2. **Aggregations** (pre-computed summaries)
3. **Business Definitions** (revenue recognition, churn definition)
4. **Dynamic Calculations** (YoY growth, moving averages)
5. **Role-Based Views** (filtered for specific user groups)

**Why**: Semantic layer provides business context without altering underlying data structures. It allows different teams to define metrics consistently.

**Example**:
```sql
-- semantic.monthly_revenue (MUST be in Semantic)
CREATE VIEW semantic.monthly_revenue AS
SELECT
  d.year,
  d.month,
  u.user_segment,
  SUM(f.total_amount) AS monthly_revenue,
  LAG(SUM(f.total_amount)) OVER (PARTITION BY u.user_segment ORDER BY d.year, d.month) AS prev_month_revenue,
  (SUM(f.total_amount) - prev_month_revenue) / NULLIF(prev_month_revenue, 0) AS mom_growth_rate
FROM gold.fact_orders f
JOIN gold.dim_date d ON f.date_key = d.date_key
JOIN gold.dim_users u ON f.user_key = u.user_key
GROUP BY 1, 2, 3;
```

#### **Must NEVER Be in Either (BI Layer Only)**:
1. **User-Specific Filters** (personal dashboards, ad-hoc queries)
2. **Visualization Logic** (chart types, colors, formatting)
3. **Ad-Hoc Calculations** (one-time analysis)
4. **Row-Level Security Filters** (unless using RLS in semantic layer)

**Why**: These are presentation-layer concerns that vary by user and use case. Encoding them in data models creates rigidity.

### 2.5 Real-Time + Historical Hybrid Architecture

**Scenario**: E-commerce dashboard needs:
- **Historical Accuracy**: Orders from last 2 years
- **Real-Time Adjustments**: Attribution windows that change based on current date

**Architecture Design**:

```
Silver Layer (Near Real-Time Streaming)
  ↓
Gold Layer (Batch Daily, Historical Facts)
  ↓
Semantic Layer (Hybrid Queries)
  ↓
BI Layer
```

#### **Silver Layer (Real-Time)**:
```sql
-- silver.orders_stream (Snowpipe Streaming or Kafka)
CREATE OR REPLACE STREAM silver.orders_stream ON TABLE silver.orders
SHOW_INITIAL_ROWS = TRUE;

-- Continuous ingestion from Kafka/Azure Event Hubs
```

#### **Gold Layer (Batch Daily)**:
```sql
-- gold.fact_orders (Historical, immutable)
-- Loaded daily via dbt, includes all historical orders
CREATE TABLE gold.fact_orders (
  order_key INT,
  user_key INT,
  product_key INT,
  date_key INT,
  order_timestamp TIMESTAMP_NTZ,
  total_amount DECIMAL(10,2),
  -- Attribution fields (static at load time)
  first_touch_channel STRING,
  last_touch_channel STRING,
  created_at TIMESTAMP_NTZ
);
```

#### **Semantic Layer (Hybrid Logic)**:
```sql
-- semantic.revenue_with_dynamic_attribution
-- Combines historical facts with real-time attribution logic
CREATE VIEW semantic.revenue_with_dynamic_attribution AS
WITH attribution_window AS (
  SELECT
    DATEADD(day, -30, CURRENT_DATE()) AS attribution_start_date
),
recent_orders AS (
  SELECT
    f.*,
    -- Recalculate attribution for orders within dynamic window
    CASE
      WHEN f.order_timestamp >= (SELECT attribution_start_date FROM attribution_window)
      THEN calculate_dynamic_attribution(f.user_key, f.order_timestamp)
      ELSE f.last_touch_channel  -- Use historical attribution for older orders
    END AS adjusted_attribution_channel
  FROM gold.fact_orders f
)
SELECT
  ro.adjusted_attribution_channel AS channel,
  DATE_TRUNC('day', ro.order_timestamp) AS order_date,
  SUM(ro.total_amount) AS revenue,
  COUNT(ro.order_key) AS order_count
FROM recent_orders ro
GROUP BY 1, 2;
```

**Key Decisions**:
1. **Silver Layer**: Real-time for alerting and operational dashboards (last 7 days)
2. **Gold Layer**: Daily batch for historical accuracy (full dataset, immutable)
3. **Semantic Layer**: Hybrid queries that:
   - Use historical attribution for old orders (immutable)
   - Recalculate attribution dynamically for recent orders (within window)
   - Surface both to BI layer based on filter context

**Why This Works**:
- **Performance**: Gold layer pre-computes expensive joins (daily batch)
- **Flexibility**: Semantic layer allows dynamic windows without reprocessing history
- **Accuracy**: Historical data remains unchanged, only recent period is recalculated
- **Scalability**: BI queries run against optimized semantic views, not raw streams

**Alternative for Extreme Real-Time Needs**:
```sql
-- semantic.realtime_revenue_hybrid
CREATE VIEW semantic.realtime_revenue_hybrid AS
-- Historical revenue from Gold (pre-computed)
SELECT * FROM gold.fact_orders WHERE order_timestamp < CURRENT_DATE()
UNION ALL
-- Today's revenue from Silver (real-time stream)
SELECT * FROM silver.orders_stream WHERE order_timestamp >= CURRENT_DATE();
```

---

## 3. Security and Governance

### 3.1 Data Security

#### **Encryption in Transit**:
- **Azure Blob ↔ Azure Function**: HTTPS/TLS 1.2+
- **Azure ↔ Snowflake**: TLS 1.2+ with Azure Storage Integration
- **Airflow ↔ Snowflake**: HTTPS with key-pair authentication
- **dbt ↔ Snowflake**: Snowflake connector with encrypted connections

#### **Encryption at Rest**:
- **Azure Blob Storage**:
  - Azure Storage Service Encryption (SSE) with Microsoft-managed keys
  - Client-side encryption with customer-managed keys (CMK) from Key Vault
- **Snowflake**:
  - Automatic encryption with AES-256
  - Support for customer-managed keys via Azure Key Vault External Functions

#### **Key Management**:
```
Azure Key Vault
  ├── Data Encryption Keys (DEK) - for Parquet file encryption
  ├── Snowflake Private Keys - for authentication
  ├── Service Principal Secrets - for Azure authentication
  └── Managed Identity Access - for Azure Functions
```

### 3.2 Access Management

#### **Azure to Snowflake Integration**:
```sql
-- 1. Create Azure Storage Integration in Snowflake
CREATE STORAGE INTEGRATION azure_blob_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '<tenant_id>'
  STORAGE_ALLOWED_LOCATIONS = ('azure://storage.blob.core.windows.net/staged-data/');

-- 2. Grant Snowflake managed identity access in Azure
-- Azure Portal → Storage Account → IAM → Add Role Assignment:
--   Role: Storage Blob Data Reader
--   Assign to: Snowflake managed identity (from STORAGE_INTEGRATION descriptor)
```

#### **Airflow to Snowflake**:
- **Method**: Snowflake Connection with key-pair authentication
- **Configuration**:
  ```python
  # airflow/connections/snowflake_connection.py
  from airflow.models import Connection

  conn = Connection(
      conn_id="snowflake_prod",
      conn_type="snowflake",
      host="<account>.snowflakecomputing.com",
      login="airflow_svc_user",
      schema="bronze",
      extra={
          "account": "<account>",
          "warehouse": "TRANSFORM_WH",
          "database": "ANALYTICS_DB",
          "role": "AIRFLOW_ROLE",
          "authenticator": "snowflake",
          "private_key_content": "{{ var.value.snowflake_private_key }}"  # Stored in Airflow Variables (encrypted)
      }
  )
  ```

### 3.3 Snowflake RBAC Model

#### **Role Hierarchy**:
```sql
-- Role hierarchy design
ACCOUNTADMIN (top-level, emergency only)
  └── SECURITYADMIN (security management)
        ├── DATA_ENGINEER_ROLE (write to Bronze/Silver/Gold)
        ├── ANALYTICS_ENGINEER_ROLE (write to Semantic)
        ├── DATA_ANALYST_ROLE (read Semantic, Gold)
        └── BI_VIEWER_ROLE (read Semantic only)
  └── SYSADMIN (warehouse/database management)
        └── DBT_TRANSFORM_ROLE (dbt transformations)
```

#### **Database-Level Privileges**:
```sql
-- Bronze database (raw data)
GRANT USAGE ON DATABASE bronze_db TO ROLE DATA_ENGINEER_ROLE;
GRANT CREATE SCHEMA ON DATABASE bronze_db TO ROLE DATA_ENGINEER_ROLE;
GRANT ALL ON ALL SCHEMAS IN DATABASE bronze_db TO ROLE DATA_ENGINEER_ROLE;

-- Silver database (cleaned data)
GRANT USAGE ON DATABASE silver_db TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON DATABASE silver_db TO ROLE ANALYTICS_ENGINEER_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE silver_db TO ROLE DATA_ANALYST_ROLE;

-- Gold database (dimensional models)
GRANT USAGE ON DATABASE gold_db TO ROLE ANALYTICS_ENGINEER_ROLE;
GRANT SELECT ON ALL TABLES IN DATABASE gold_db TO ROLE DATA_ANALYST_ROLE;

-- Semantic database (business metrics)
GRANT USAGE ON DATABASE semantic_db TO ROLE ANALYTICS_ENGINEER_ROLE;
GRANT SELECT ON ALL VIEWS IN DATABASE semantic_db TO ROLE BI_VIEWER_ROLE;
```

#### **Warehouse Privileges**:
```sql
-- Separate warehouses by workload
CREATE WAREHOUSE ingestion_wh WITH WAREHOUSE_SIZE = 'SMALL' AUTO_SUSPEND = 60;
CREATE WAREHOUSE transform_wh WITH WAREHOUSE_SIZE = 'MEDIUM' AUTO_SUSPEND = 300;
CREATE WAREHOUSE analytics_wh WITH WAREHOUSE_SIZE = 'LARGE' AUTO_SUSPEND = 60;

GRANT USAGE ON WAREHOUSE ingestion_wh TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON WAREHOUSE transform_wh TO ROLE DBT_TRANSFORM_ROLE;
GRANT USAGE ON WAREHOUSE analytics_wh TO ROLE DATA_ANALYST_ROLE;
```

#### **Row-Level Security (RLS)**:
```sql
-- Example: Regional data isolation
CREATE ROW ACCESS POLICY region_policy AS (region_col STRING) RETURNS BOOLEAN ->
  CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SECURITYADMIN') THEN TRUE
    WHEN CURRENT_ROLE() = 'EU_ANALYST_ROLE' AND region_col = 'EU' THEN TRUE
    WHEN CURRENT_ROLE() = 'US_ANALYST_ROLE' AND region_col = 'US' THEN TRUE
    ELSE FALSE
  END;

-- Apply to table
ALTER TABLE gold.fact_orders
  ADD ROW ACCESS POLICY region_policy ON (region);
```

#### **Column-Level Security (Masking)**:
```sql
-- PII masking policy
CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN ('DATA_ENGINEER_ROLE', 'ACCOUNTADMIN') THEN val
    WHEN CURRENT_ROLE() IN ('DATA_ANALYST_ROLE') THEN REGEXP_REPLACE(val, '^(.{2}).*(@.*)$', '\\1***\\2')
    ELSE '***@***.com'
  END;

-- Apply to column
ALTER TABLE gold.dim_users
  MODIFY COLUMN user_email SET MASKING POLICY email_mask;
```

#### **Service Account Roles**:
```sql
-- Airflow service account
CREATE ROLE airflow_role;
GRANT USAGE ON WAREHOUSE ingestion_wh TO ROLE airflow_role;
GRANT ALL ON SCHEMA bronze_db.raw_data TO ROLE airflow_role;

CREATE USER airflow_svc_user
  RSA_PUBLIC_KEY = '<public_key_from_airflow>'
  DEFAULT_ROLE = airflow_role;

GRANT ROLE airflow_role TO USER airflow_svc_user;

-- dbt service account
CREATE ROLE dbt_role;
GRANT USAGE ON WAREHOUSE transform_wh TO ROLE dbt_role;
GRANT SELECT ON ALL SCHEMAS IN DATABASE bronze_db TO ROLE dbt_role;
GRANT ALL ON ALL SCHEMAS IN DATABASE silver_db TO ROLE dbt_role;
GRANT ALL ON ALL SCHEMAS IN DATABASE gold_db TO ROLE dbt_role;
GRANT ALL ON ALL SCHEMAS IN DATABASE semantic_db TO ROLE dbt_role;

CREATE USER dbt_svc_user
  RSA_PUBLIC_KEY = '<public_key_from_dbt>'
  DEFAULT_ROLE = dbt_role;

GRANT ROLE dbt_role TO USER dbt_svc_user;
```

### 3.4 Data Governance

#### **Data Lineage**:
- **Snowflake**: Use `ACCESS_HISTORY` and `QUERY_HISTORY` views
- **dbt**: Built-in lineage graphs via `dbt docs generate`
- **Third-Party**: Integrate with Alation, Collibra, or Atlan

#### **Data Quality**:
```sql
-- dbt tests (tests/data_quality/)
-- tests/assert_no_null_customer_ids.sql
{{ config(severity='error') }}

SELECT *
FROM {{ ref('silver_customers') }}
WHERE customer_id IS NULL;

-- tests/assert_revenue_positive.sql
{{ config(severity='warn') }}

SELECT *
FROM {{ ref('gold_fact_orders') }}
WHERE total_amount < 0;
```

#### **Audit Logging**:
```sql
-- Enable Snowflake query logging
ALTER ACCOUNT SET QUERY_LOGGING = TRUE;

-- Create audit table for sensitive access
CREATE TABLE audit.access_log AS
SELECT
  query_id,
  user_name,
  role_name,
  database_name,
  schema_name,
  query_text,
  execution_time,
  rows_produced
FROM snowflake.account_usage.query_history
WHERE schema_name IN ('gold', 'semantic')
  AND execution_status = 'SUCCESS';
```

---

## 4. Operational Considerations

### 4.1 Monitoring

#### **Pipeline Monitoring (Airflow)**:
```python
# airflow/dags/encrypted_parquet_pipeline.py
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator

def failure_callback(context):
    slack_msg = f"""
    :red_circle: Pipeline Failed
    *DAG*: {context.get('task_instance').dag_id}
    *Task*: {context.get('task_instance').task_id}
    *Execution Time*: {context.get('execution_date')}
    *Log*: {context.get('task_instance').log_url}
    """
    SlackWebhookOperator(
        task_id='slack_alert',
        http_conn_id='slack_webhook',
        message=slack_msg
    ).execute(context=context)

default_args = {
    'on_failure_callback': failure_callback,
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
}
```

#### **Data Quality Monitoring (dbt)**:
```yaml
# dbt_project.yml
models:
  +meta:
    owner: "data-engineering@company.com"

  silver:
    +on-run-end:
      - "{{ log_test_results() }}"  # Custom macro to log test results

# macros/log_test_results.sql
{% macro log_test_results() %}
  INSERT INTO monitoring.dbt_test_results
  SELECT
    '{{ run_started_at }}' AS run_timestamp,
    '{{ invocation_id }}' AS invocation_id,
    model_name,
    test_name,
    status,
    execution_time
  FROM {{ ref('dbt_test_results_ephemeral') }};
{% endmacro %}
```

#### **Snowflake Monitoring**:
```sql
-- Query performance monitoring
CREATE OR REPLACE VIEW monitoring.slow_queries AS
SELECT
  query_id,
  user_name,
  warehouse_name,
  execution_time / 1000 AS execution_seconds,
  total_elapsed_time / 1000 AS total_seconds,
  bytes_scanned,
  rows_produced,
  query_text
FROM snowflake.account_usage.query_history
WHERE execution_time > 60000  -- Queries > 1 minute
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY execution_time DESC;

-- Warehouse credit usage
CREATE OR REPLACE VIEW monitoring.warehouse_usage AS
SELECT
  warehouse_name,
  DATE_TRUNC('day', start_time) AS usage_date,
  SUM(credits_used) AS daily_credits,
  SUM(credits_used) * 4 AS estimated_monthly_cost  -- Assuming $4/credit
FROM snowflake.account_usage.warehouse_metering_history
GROUP BY 1, 2
ORDER BY 1, 2 DESC;
```

### 4.2 Testing

#### **Unit Tests (dbt)**:
```sql
-- models/silver/silver_orders.sql
{{ config(
    materialized='table',
    tags=['silver', 'orders']
) }}

WITH source AS (
  SELECT * FROM {{ source('bronze', 'raw_orders') }}
),

cleaned AS (
  SELECT
    order_id,
    customer_id,
    order_date,
    COALESCE(total_amount, 0) AS total_amount
  FROM source
  WHERE order_id IS NOT NULL
)

SELECT * FROM cleaned;

-- tests/silver/test_silver_orders.yml
version: 2

models:
  - name: silver_orders
    description: Cleaned order data
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - order_id
    columns:
      - name: order_id
        tests:
          - not_null
          - unique
      - name: customer_id
        tests:
          - not_null
          - relationships:
              to: ref('silver_customers')
              field: customer_id
      - name: total_amount
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
              max_value: 1000000
```

#### **Integration Tests (Airflow)**:
```python
# tests/integration/test_pipeline.py
import pytest
from airflow.models import DagBag

def test_dag_loaded():
    dagbag = DagBag()
    assert len(dagbag.import_errors) == 0

def test_dag_structure():
    dagbag = DagBag()
    dag = dagbag.get_dag('encrypted_parquet_pipeline')

    assert dag is not None
    assert len(dag.tasks) == 9
    assert 'decrypt_and_stage' in [task.task_id for task in dag.tasks]

def test_decrypt_function(mock_blob_storage):
    # Mock Azure Function call
    response = decrypt_azure_function.run(mock_encrypted_file)
    assert response.status_code == 200
    assert 'row_count' in response.json()
```

#### **End-to-End Tests**:
```bash
# tests/e2e/test_full_pipeline.sh
#!/bin/bash

# 1. Upload test encrypted file to blob storage
az storage blob upload \
  --account-name stagedstorage \
  --container-name raw-encrypted-data \
  --name test/test_data.parquet.encrypted \
  --file tests/fixtures/sample_encrypted.parquet

# 2. Trigger Airflow DAG
airflow dags trigger encrypted_parquet_pipeline

# 3. Wait for completion
airflow dags state encrypted_parquet_pipeline <execution_date>

# 4. Validate data in Snowflake
snowsql -q "SELECT COUNT(*) FROM gold.fact_orders WHERE created_at >= CURRENT_DATE();"

# 5. Clean up
airflow dags delete encrypted_parquet_pipeline <execution_date>
```

### 4.3 Deployment

#### **CI/CD Pipeline (GitHub Actions)**:
```yaml
# .github/workflows/deploy_dbt.yml
name: Deploy dbt Models

on:
  push:
    branches: [main]
    paths:
      - 'dbt/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install dbt
        run: pip install dbt-snowflake

      - name: dbt deps
        run: dbt deps
        working-directory: ./dbt

      - name: dbt compile
        run: dbt compile --target dev
        working-directory: ./dbt

      - name: dbt test
        run: dbt test --target dev
        working-directory: ./dbt

  deploy:
    needs: test
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v3

      - name: Install dbt
        run: pip install dbt-snowflake

      - name: dbt run (slim CI)
        run: |
          dbt run --target prod --select state:modified+
        working-directory: ./dbt
        env:
          SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
          SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_PRIVATE_KEY: ${{ secrets.SNOWFLAKE_PRIVATE_KEY }}

      - name: dbt docs generate
        run: dbt docs generate --target prod
        working-directory: ./dbt
```

#### **Blue-Green Deployment for dbt**:
```sql
-- Step 1: Create new schema (green)
CREATE SCHEMA gold_green CLONE gold;

-- Step 2: Run dbt against green schema
-- dbt_project.yml
{{ target.name }}_schema: "gold_{{ 'green' if var('deployment_color') == 'green' else 'blue' }}"

-- Step 3: Validate green schema
-- Run smoke tests, compare row counts

-- Step 4: Swap schemas
ALTER SCHEMA gold SWAP WITH gold_green;

-- Step 5: Drop old schema after validation period
DROP SCHEMA gold_green;
```

### 4.4 Failure Handling

#### **Schema Changes**:
```python
# airflow/dags/operators/schema_validator.py
class SchemaValidationOperator(BaseOperator):
    def execute(self, context):
        # 1. Detect schema drift
        current_schema = self.get_current_schema()
        expected_schema = self.get_expected_schema()

        drift = self.compare_schemas(current_schema, expected_schema)

        if drift.has_breaking_changes:
            # 2. Trigger alert
            self.send_alert(drift)

            # 3. Create new table version
            self.create_table_v2(drift.new_columns)

            # 4. Dual-write to both versions during transition
            self.enable_dual_write()

            raise AirflowException("Breaking schema change detected")

        elif drift.has_new_columns:
            # Non-breaking: Add columns dynamically
            self.alter_table_add_columns(drift.new_columns)
```

#### **Data Quality Issues**:
```sql
-- Create quarantine table for failed records
CREATE TABLE quarantine.failed_records (
  record_id STRING,
  source_table STRING,
  failure_reason STRING,
  record_payload VARIANT,
  failed_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- dbt macro for quarantine
{% macro quarantine_failed_records(model_name, quality_check) %}
  INSERT INTO quarantine.failed_records (record_id, source_table, failure_reason, record_payload)
  SELECT
    record_id,
    '{{ model_name }}',
    '{{ quality_check }}',
    OBJECT_CONSTRUCT(*) AS record_payload
  FROM {{ ref(model_name) }}
  WHERE NOT {{ quality_check }};

  DELETE FROM {{ ref(model_name) }}
  WHERE NOT {{ quality_check }};
{% endmacro %}
```

#### **Pipeline Failures**:
```python
# airflow/dags/encrypted_parquet_pipeline.py
from airflow.operators.python import BranchPythonOperator

def check_failure_type(**context):
    ti = context['task_instance']
    failed_task = ti.xcom_pull(key='failed_task_id')

    if failed_task == 'decrypt_and_stage':
        return 'retry_decrypt'
    elif failed_task == 'dbt_run_bronze':
        return 'rollback_bronze'
    else:
        return 'send_alert_and_skip'

with DAG('encrypted_parquet_pipeline') as dag:
    # ... other tasks

    failure_handler = BranchPythonOperator(
        task_id='handle_failure',
        python_callable=check_failure_type,
        trigger_rule='one_failed'
    )

    retry_decrypt = PythonOperator(
        task_id='retry_decrypt',
        python_callable=retry_decryption_with_backoff
    )

    rollback_bronze = SnowflakeOperator(
        task_id='rollback_bronze',
        sql="DELETE FROM bronze.raw_customer_data WHERE ingestion_timestamp >= '{{ ts }}';"
    )
```

### 4.5 Performance Optimization

#### **Snowflake Clustering**:
```sql
-- Cluster large fact tables by date
ALTER TABLE gold.fact_orders CLUSTER BY (order_date);

-- Multi-column clustering for dimensional queries
ALTER TABLE gold.fact_clickstream_events CLUSTER BY (event_date, user_id);
```

#### **Materialized Views for Semantic Layer**:
```sql
-- Replace view with materialized view for frequently accessed metrics
CREATE MATERIALIZED VIEW semantic.daily_revenue_mv AS
SELECT
  DATE_TRUNC('day', order_timestamp) AS order_date,
  SUM(total_amount) AS daily_revenue,
  COUNT(DISTINCT user_id) AS unique_customers
FROM gold.fact_orders
GROUP BY 1;

-- Refresh incrementally
ALTER MATERIALIZED VIEW semantic.daily_revenue_mv RESUME;
```

#### **dbt Incremental Models**:
```sql
-- models/silver/silver_orders.sql
{{ config(
    materialized='incremental',
    unique_key='order_id',
    on_schema_change='fail'
) }}

SELECT * FROM {{ source('bronze', 'raw_orders') }}

{% if is_incremental() %}
  WHERE ingestion_timestamp > (SELECT MAX(updated_at) FROM {{ this }})
{% endif %}
```

---

## 5. Control Plane: Implicit Conditions for Production Readiness

**Key Insight**: File size determines "can it run?" — Implicit conditions determine "can it pass audit and survive production?"

Beyond technical execution, this architecture addresses **9 implicit conditions** that auditors and production systems demand but requirements documents rarely specify:

### 5.1 The Nine Implicit Conditions

#### **Condition 1: Data Sensitivity & Minimal Exposure**

**Question**: Is data allowed to exist as plaintext? Can engineers see it? Can it be cached?

**Architectural Controls**:
- ✅ Decryption only in **secure compute boundary** (Azure Function with managed identity)
- ✅ Plaintext **never persisted** long-term (TTL on decrypted zone)
- ✅ PII **masked by default** in Silver/Gold/Semantic layers
- ✅ **No PII in logs** or error messages

**Compliance**: Privacy Act + APRA CPS 234

#### **Condition 2: Idempotency & Duplicate Handling**

**Question**: What if files arrive multiple times? Out of order? Same day, different versions?

**Architectural Controls**:
- ✅ `file_hash` (SHA-256) to detect duplicates
- ✅ `batch_id` in control table to track ingestion runs
- ✅ `COPY INTO` with `MATCH_BY_COLUMN_NAME` and `ON_ERROR = 'SKIP_FILE'`
- ✅ Deduplication strategy in Silver layer (QUALIFY ROW_NUMBER)

**Production Impact**: Prevents data duplication that causes reporting errors

#### **Condition 3: Time Semantics (Event Time vs Process Time)**

**Question**: When is data "effective"? File arrival time? Business event time? Ingestion time?

**Architectural Controls**:
- ✅ **Event time**: Preserved from source data (`order_date`, `transaction_timestamp`)
- ✅ **Process time**: `ingestion_timestamp`, `transformation_timestamp`
- ✅ **Late-arriving data**: Handled via `event_time` logic in Silver/Gold
- ✅ **Backfill strategy**: Clear separation of business and system time

**Example**:
```sql
-- Silver layer: Separate event time from process time
SELECT
  event_payload:order_date::DATE AS order_date,  -- Event time
  CURRENT_TIMESTAMP() AS ingestion_timestamp     -- Process time
FROM bronze.raw_orders;
```

**Compliance**: Ensures historical consistency and correct reporting windows

#### **Condition 4: Failure Modes & Recovery**

**Question**: If failure occurs, is it manual re-run? Auto-recovery? Partial success?

**Architectural Controls**:
- ✅ **Quarantine zone**: Bad files/records isolated, not blocking pipeline
- ✅ **Bronze immutability**: Can always re-process from raw data
- ✅ **Incremental re-run**: Silver/Gold support targeted recalculation by `batch_id`
- ✅ **Failure isolation**: dbt models fail independently without cascading

**Implementation**:
```sql
-- Quarantine table for failed records
CREATE TABLE quarantine.failed_records (
  record_id STRING,
  source_table STRING,
  failure_reason STRING,
  record_payload VARIANT,
  failed_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

**Compliance**: APRA CPS 230 (Operational Risk)

#### **Condition 5: Auditability & Reproducibility**

**Question**: Can we reproduce this calculation from 12 months ago? Who changed the rule?

**Architectural Controls**:
- ✅ **Data lineage**: dbt automatically generates DAG and column-level lineage
- ✅ **Rule versioning**: dbt models in Git with commit SHA embedded in metadata
- ✅ **Run traceability**: `batch_id` + `execution_date` + `dbt_model_version`
- ✅ **Access logging**: Snowflake `QUERY_HISTORY` and `ACCESS_HISTORY`

**Reproducibility Pattern**:
```sql
-- Metadata table for audit trail
CREATE TABLE metadata.transformation_runs (
  run_id STRING,
  batch_id STRING,
  dbt_model STRING,
  dbt_git_sha STRING,
  execution_date DATE,
  row_count INT,
  run_timestamp TIMESTAMP_NTZ
);
```

**Compliance**: ASIC reporting + APRA data reproducibility requirements

#### **Condition 6: Key & Secret Management**

**Question**: Are keys in code? In variables? How is rotation handled?

**Architectural Controls**:
- ✅ **Azure Key Vault**: All keys and secrets centralized
- ✅ **Managed Identity**: Azure Function accesses Key Vault without passwords
- ✅ **No secrets in DAGs**: Airflow connections use Key Vault backend
- ✅ **Key rotation**: Automated via Azure Key Vault policies
- ✅ **Limited blast radius**: Decryption keys scoped to specific compute context

**Anti-Patterns to Avoid**:
- ❌ Private keys in Git
- ❌ Secrets in environment variables
- ❌ Hardcoded connection strings

**Compliance**: APRA CPS 234 (Information Security)

#### **Condition 7: Access Control & Governance**

**Question**: Can analysts accidentally expose PII? Can new users "safely" use the platform?

**Architectural Controls**:
- ✅ **Snowflake RBAC**: Engineering / Analytics / BI roles separated
- ✅ **Masking policies**: PII redacted by default
- ✅ **Row-level security**: Business unit data isolation
- ✅ **Semantic layer**: Analysts query pre-defined, safe metrics (not raw tables)
- ✅ **Default deny**: Permissions are opt-in, not opt-out

**Design Philosophy**: "System prevents mistakes" > "Users are careful"

**Compliance**: Privacy Act (access minimization) + CPS 234 (access control)

#### **Condition 8: Schema Evolution & Change Management**

**Question**: What if source adds a column? Changes a type? Renames a field?

**Architectural Controls**:
- ✅ **Schema detection**: dbt `on_schema_change` config
- ✅ **Backward compatibility**: Bronze layer flexible (VARIANT for JSON)
- ✅ **Version coexistence**: Old and new schemas can coexist during transition
- ✅ **Contract enforcement**: dbt contracts for critical downstream dependencies

**Implementation**:
```yaml
# dbt model config
{{ config(
    on_schema_change='fail',  # or 'append_new_columns', 'sync_all_columns'
    contract={'enforced': true}
) }}
```

**Production Impact**: Prevents silent data loss from schema drift

#### **Condition 9: Operational Observability**

**Question**: How do we know if the pipeline is healthy? Slow? Expensive?

**Architectural Controls**:
- ✅ **SLA monitoring**: Airflow tracks DAG run duration and alerts on delays
- ✅ **Data quality tests**: dbt tests run automatically, failures trigger alerts
- ✅ **Freshness checks**: `dbt source freshness` ensures data is not stale
- ✅ **Cost tracking**: Snowflake warehouse credit usage monitored
- ✅ **Row count validation**: Downstream layers validated against upstream counts

**Monitoring Dashboard Metrics**:
- Pipeline success rate (last 30 days)
- Average DAG runtime (by execution date)
- dbt test failure rate
- Snowflake warehouse credit consumption (daily)
- Data freshness (time since last ingestion)

**Compliance**: APRA CPS 230 (operational resilience)

### 5.2 Control Plane Summary

| Implicit Condition | Affects These Components | Key Controls |
|-------------------|--------------------------|--------------|
| **Data Sensitivity** | Azure Function, Silver/Gold/Semantic, BI | Key Vault, Masking, TTL |
| **Idempotency** | Airflow, Bronze (COPY INTO), Silver | file_hash, batch_id, deduplication |
| **Time Semantics** | Silver, Gold, Semantic | event_time vs process_time, late arrivals |
| **Failure Recovery** | All layers | Quarantine, immutable Bronze, incremental re-run |
| **Auditability** | dbt, Airflow, Snowflake | Lineage, Git versioning, access history |
| **Key Management** | Azure Function, Snowflake connection | Key Vault, managed identity, rotation |
| **Access Governance** | Snowflake (all layers), BI | RBAC, masking, row policies, semantic layer |
| **Schema Evolution** | Bronze → Silver → Gold | on_schema_change, contracts, VARIANT types |
| **Observability** | Airflow, dbt, Snowflake | SLA, tests, freshness, cost monitoring |

### 5.3 Interview Positioning Statement

> "Beyond file size, the design is driven by implicit constraints—**data sensitivity, idempotency, time semantics, failure recovery, and auditability**. If these aren't addressed upfront, the pipeline may work technically but will **fail under compliance review or real operational pressure**."

---

## 6. Architecture Diagrams

### 6.1 Data Plane (End-to-End Pipeline)

See `diagrams/data-plane.mmd` for the complete Mermaid flowchart.

**High-level flow**:
1. Encrypted Parquet file lands in Azure Blob Storage
2. Airflow detects file and validates name + checksum
3. Azure Function fetches decryption key from Key Vault (managed identity)
4. Decryption occurs in secure compute boundary (short-lived plaintext)
5. Decrypted file staged to temporary blob container (TTL)
6. Snowflake COPY INTO loads data to Bronze (immutable, raw)
7. dbt transforms: Bronze → Silver → Gold → Semantic
8. BI layer consumes Semantic layer (governed access)

### 6.2 Control Plane (Implicit Conditions)

See `diagrams/control-plane.mmd` for the complete Mermaid diagram.

**Control mechanisms** attached to pipeline stages:
- **PII Handling**: Masking policies at Silver/Gold/Semantic/BI
- **Idempotency**: file_hash + batch_id at Ingestion & Bronze
- **Time Semantics**: event_time vs process_time in Silver/Gold modeling
- **Failure Recovery**: Quarantine tables + replay by batch_id
- **Auditability**: dbt artifacts + Airflow run metadata
- **Key Management**: Key Vault integration at decryption stage
- **Access Control**: Snowflake RBAC/policies across all consumption layers
- **Schema Evolution**: dbt contracts + on_schema_change at Bronze → Silver
- **Observability**: Monitoring integrated across Airflow, dbt, Snowflake, Azure

---

## 7. Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Set up Azure infrastructure (Blob Storage, Key Vault, Functions)
- [ ] Configure Snowflake (databases, warehouses, roles)
- [ ] Implement encryption/decryption pipeline
- [ ] Set up Airflow (local or cloud)

### Phase 2: Data Pipeline (Week 3-4)
- [ ] Build Bronze layer (COPY INTO from external stage)
- [ ] Build Silver layer (dbt models for cleaning)
- [ ] Build Gold layer (dimensional models)
- [ ] Implement data quality tests

### Phase 3: Advanced Features (Week 5-6)
- [ ] Build Semantic layer (metrics, aggregations)
- [ ] Implement RBAC and data masking
- [ ] Set up monitoring and alerting
- [ ] Create CI/CD pipelines

### Phase 4: Production Hardening (Week 7-8)
- [ ] Performance optimization (clustering, materialized views)
- [ ] Disaster recovery and backup procedures
- [ ] Documentation and runbooks
- [ ] User training and handoff
