# Customer Data Flow (Generation → MySQL → dbt Layers → Metrics)

This note walks through how the synthetic customer data that powers the local test environment is created, lands in MySQL, and progresses through dbt’s bronze, silver, gold (dimension), and semantic/metrics layers.

---

## 1. Synthetic Data Generation
**Script:** `local_test/scripts/generate_data.py`

- Uses NumPy/Pandas with a fixed random seed to produce **change-log style customer events** plus 5,000 orders, saved as Parquet files under `local_test/data/decrypted/`.
- For customers, the generator now emits inserts, updates, and deactivations across multi-week periods to simulate attrition:
  - Week 1 starts with ~1,000 active customers (`change_type='insert'` for the initial load).
  - Week 2 contracts the active population to ~500 by emitting deactivation events.
  - Week 3 contracts further to ~100.
  - Weeks 4–5 taper to ~10 active customers and stay flat, creating a long-tail of loyal accounts.
  - At each step, ~10% of the currently active population receives profile updates (`change_type='update'`) that modify phone, country, or segment.
- Every event includes an `effective_at` timestamp so downstream layers can order changes chronologically.
- Intentional data-quality issues remain:
  - ~1% of customer IDs are set to `NULL` and ~2% of emails to `NULL`.
  - Orders include ~0.5% negative amounts and ~1% missing order IDs.
- The script prints the change-type distribution, segment/country splits, and instructions for encryption.

## 2. Encryption & Landing
**Script:** `local_test/scripts/encrypt_parquet.py`

- Encrypts each Parquet file with Fernet (AES-128) using the persistent key at `local_test/keys/encryption.key`.
- Writes encrypted payloads plus metadata (hash, sizes, timestamp) to `local_test/data/encrypted/`.
- Verifies encrypted files are unreadable as Parquet, mirroring the “encrypted Blob landing zone” step from the reference architecture.

## 3. Loading Parquet into MySQL (Raw Source Tables)
**DAG task:** `load_to_mysql` inside `local_test/airflow/dags/local_encrypted_pipeline.py`

- After Airflow decrypts a landing file, the task reads the decrypted Parquet via pandas, infers whether it’s a customer or order file, and writes it to MySQL using SQLAlchemy.
- Tables populated: `nocodb_db.src_customers` and `nocodb_db.src_orders`. Each run replaces the content (`if_exists='replace'`) to keep the staging seed consistent.

## 4. dbt Bronze Layer (`models/bronze/`)

### `bronze_customers.sql`
- Selects directly from `nocodb_db.src_customers`.
- Captures the source columns plus batch metadata:
  - `change_type` + `effective_at` arrive from the encrypted feed.
  - `batch_id` / `execution_date` (via `dbt_project.yml`) and `ingestion_timestamp` are added for traceability.
- Materialized as a table tagged `bronze` so dbt lineage shows “raw, immutable snapshot” for each change event.

### `bronze_orders.sql`
- Mirrors the customers model for order data, keeping raw timestamps, order_status, amount, currency, etc., with the same metadata columns.

> **Note:** Because Airflow writes to the `src_*` tables first, the bronze models act as the “Merge into Bronze” step—dbt copies the raw snapshot, preserving batch context and isolating downstream transformations from staging churn.

## 5. dbt Silver Layer (`models/silver/`)

### `silver_customers.sql`
- Base is `ref('bronze_customers')`.
- Cleansing operations:
  - Trims names, lowercases emails, uppercases countries, and casts `registration_date`.
  - Normalizes `is_active` while respecting the CDC feed (deactivations always set it to `FALSE`).
  - Computes `change_timestamp` from `effective_at` and derives a friendly `lifecycle_state`.
  - Adds `transformation_timestamp` and `data_quality_flag` fields.
  - Deduplicates by `customer_id` ordering on `change_timestamp` (if present) then `ingestion_timestamp`.
- Output filters to `row_num = 1`, ensuring a single **current-state** record per customer while keeping the CDC metadata (`change_type`, `change_timestamp`, `lifecycle_state`) for auditability.

### `silver_orders.sql`
- Casts dates/timestamps, enforces decimal precision on amounts, uppercases currency, and keeps payment metadata.
- Flags anomalies: missing IDs/customer IDs, negative or suspiciously high amounts.
- Deduplicates by `order_id`, retaining the latest ingestion per key.

These silver models embody the “cleaned and standardized” layer described in the architecture memo, retaining `batch_id`, `execution_date`, and timestamps for traceability.

## 6. Gold Layer – Customer Dimensions

### `models/gold/dim_customers.sql` (current-state dimension)
- Consumes `ref('silver_customers')` and filters to `data_quality_flag IS NULL`, so only validated rows advance to analytics.
- Adds derived columns:
  - `full_name`, `days_since_registration`, `registration_year`, `registration_quarter`.
  - `change_type`, `change_timestamp`, and `lifecycle_state`, plus a human-readable `customer_status` (“Active”, “Inactive”, “Former Customer”).
  - `source_batch_id` and `updated_at` for lineage/audit.
- Materialized as a table tagged `gold/dimension`, representing the curated **current** customer dimension consumed downstream.

### `models/gold/dim_customers_scd2.sql` (history-preserving dimension)
- Builds on the raw Bronze change events instead of the deduped silver view so every profile change/deactivation becomes its own row.
- Orders events by their `effective_at` (or ingestion) timestamp and computes `valid_from`, `valid_to`, and `is_current` windows per `customer_id`.
- Retains the same business attributes (names, country, segment, `customer_status`) along with the original `change_type`, enabling time-travel analyses and regulator-friendly audit trails.
- Tagged as `gold/dimension/scd2` so analysts can choose between “latest only” or “full history” dimensions via dbt selectors.

## 7. Fact Tables and Metrics

### Fact Models
- `models/gold/fact_orders.sql`: Joins `silver_orders` to `silver_customers` to add `customer_segment`, `country`, and metadata, exposing a dimensional fact table (`order_id` grain).
- `models/gold/fct_orders.sql`: Simplified fact (order-level) used by semantic views; after recent fixes it also includes the necessary customer attributes.

### Semantic / Metrics Layer (`models/semantic/`)
- `customer_metrics.sql`: Aggregates `dim_customers` and `fact_orders` to produce per-customer KPIs: total/completed/cancelled orders, revenue, last/first order dates, customer status (Active/At Risk/etc.), and recency buckets.
- `customer_snapshot_daily.sql`: Summarizes the SCD2 change feed by day, exposing counts of inserts/updates/deactivations and a running estimate of active customers so attrition trends are visible without querying the full history table.
- `daily_revenue.sql`: Summaries by `order_date`, year/quarter/month, country, and segment; reports completed/pending revenue, average order value, max/min order amount, etc.
- `order_metrics.sql`: Segment × country aggregates (order counts, gross revenue, average order value, date boundaries).

These views demonstrate how business-ready metrics are layered on top of the governed dimension/fact objects while preserving the lineage back to silver/bronze and ultimately to the generated Parquet files.

---

### Key Takeaways
- **Deterministic generation**: Synthetic customers/orders come with baked-in DQ issues so silver/gold/semantic tests can be exercised deterministically.
- **Controlled landing**: Encrypted files ensure the “minimum exposure” principle before Airflow decrypts and loads into MySQL.
- **Layered transformations**: dbt models explicitly separate raw capture (bronze), cleaning/deduplication (silver), conformed dimension/facts (gold), and business metrics (semantic), mirroring the production-intended architecture.
- **Traceable metadata**: Batch IDs, execution dates, ingestion/transformation timestamps, and data-quality flags persist through each layer, enabling audit-friendly lineage from the final metric back to the original generated record.
