# Secure Customer Data Pipeline Architecture

This design is framed for regulators first: it embeds the four themes Australian financial regulators expect—minimal exposure, strong control, full traceability, and replayability—directly into the data lifecycle so the pipeline is “born compliant” rather than patched after the fact.

## 1. End-to-End Data Plane
**Flow Overview**
1. An external system drops an encrypted Parquet file into `landing` on Azure Blob Storage with customer data enveloped using an RSA key pair managed by Azure Key Vault (AKV); the file only exists as ciphertext at rest.
2. Airflow (running on Azure Kubernetes Service or ACI, depending on the deployment described in `infra/`) uses a FileSensor/FilenameWatcher operator to detect the new blob, retrieves the key reference (never the key material) from AKV via a managed identity, and launches a containerized `ingest` task that is tagged with a `run_id/batch_id`.
3. The `ingest` task downloads the blob into an ephemeral pod/ACI, decrypts it with the AKV key, and stages the raw file into ADLS Gen2 Bronze plus a Snowflake external stage created via Terraform (`baseline/infra` layers). Decrypted data lives only on encrypted ephemeral disks with TTL policies.
4. A second Airflow task copies the Bronze asset into Snowflake using `COPY INTO` with end-to-end TLS and `file_hash` dedup checks. It writes to a `RAW.CUSTOMER_LANDING` table partitioned by `load_date` and keyed by `batch_id`.
5. Airflow then runs a containerized dbt job (same artifact produced by `tpch_transform/Dockerfile`) that executes `dbt build --select +models.customer*`. dbt models implement Silver cleansing, surveillance-grade data quality tests, and Gold dimensional marts; tests live in `tpch_transform/tests/`.
6. Once dbt finishes, Airflow triggers downstream consumers (Materialized Views, BI refresh webhooks) and archives the source file into `landing/archive/`, or `landing/quarantine/` if any control fails.

**Component Integration**
- Airflow DAG: tasks = `watch_blob`, `decrypt_stage`, `copy_to_snowflake`, `dbt_build`, `notify`. Airflow variables store storage account names; Secrets backend fetches connection strings from AKV.
- Azure Blob Storage/ADLS: versioning enabled, lifecycle rules to purge landing after archival; VNet integration plus Private Endpoints to Snowflake via Azure Private Link.
- Snowflake: external stage referencing secure SAS token, `RAW`, `SILVER`, `GOLD`, and `SEMANTIC` databases with `PIPE_EXECUTION` role used by Airflow.
- dbt: models deployed via container image stored in Azure Container Registry; orchestrated by Airflow or GitHub Actions for CI.

## 2. Regulatory Alignment & Control Plane
**Regulator Questions Mapped to Controls**
1. *Is sensitive data unnecessarily exposed?* Encryption-in-Blob + controlled decrypt zones + Short-TTL storage satisfy Privacy Act “minimal exposure”.
2. *Who touched which data and when?* Airflow DAG metadata, dbt artifacts, and Snowflake ACCESS_HISTORY tie every row back to `run_id/batch_id`, meeting APRA CPS 230 traceability.
3. *Can data be silently corrupted?* Bronze is append-only, Silver includes schema checks, dbt tests enforce referential/PII constraints—covering CPS 235 data risk controls.
4. *Can we isolate and recover failures?* Quarantine zones, replayable batches, and idempotent COPY operations provide controlled rollback/resubmit.
5. *Can history be recomputed?* Immutable RAW + versioned dbt models + snapshots make historical replays deterministic.
6. *Are keys/permissions centralized and auditable?* AKV handles secrets with rotation, Snowflake RBAC segregates duties (pipeline vs analyst), fulfilling CPS 234 expectations.

**Control Plane Hooks**
- **PII minimization:** plaintext only exists inside “secure compute boundary” containers, never in Airflow metadata or Blob landing.
- **Idempotency:** `file_hash` + ingestion control tables block duplicate copies; run metadata stored in Snowflake operational tables.
- **Time semantics:** Silver models capture both `event_time` and `ingest_time`, while dbt macros implement late-arrival tolerances.
- **Failure isolation:** unsuccessful decrypt or dq runs move payloads to `landing/quarantine/` with PagerDuty alerts and replay instructions.
- **Audit & lineage:** dbt docs, exposures, and manifest artifacts are retained per batch; Airflow logs archived in Azure Monitor for seven years.
- **Key & secret management:** no secrets in DAG code; AKV + Managed Identity supply scoped tokens with rotation tracked in Terraform state.
- **Governed evolution:** schema contracts defined through dbt `sources` and `on_schema_change: fail`; change-advisory boards review Gold-level logic before merge.
- **Observability:** SLA miss alerts, row-count reconciliation, and Snowflake credit monitoring feed a shared control dashboard consumed by Risk & Audit.

## 3. Lakehouse Architecture & Dimensional Modelling
**Bronze ➜ Gold JSON Log Pipeline**
1. **Bronze:** land raw JSON logs from application services into ADLS `bronze/app_logs/` with metadata (source system, ingestion ts). No schema enforcement.
2. **Silver:** use Spark or dbt incremental models to normalize JSON, flatten nested structures, and enforce schemas (cast timestamps, derive geo fields). Store results in `silver.app_events_clean`.
3. **Gold:** create dimensional models (fact_sessions, dim_user, dim_device) using dbt; apply aggregations, surrogate keys, SCD handling. Gold tables feed Materialized Views or Snowflake Data Shares.

**Lakehouse vs Cloud Data Warehouse**
- A Lakehouse unifies data lake storage (open formats, low-cost object storage) with warehouse-style governance and compute engines; it supports multi-modal data and decoupled storage/compute. A modern cloud data warehouse (like Snowflake) abstracts storage and compute but typically expects structured data and manages metadata internally. The proposed architecture leverages both: Blob/ADLS for Bronze/Silver persistence and Snowflake for governed compute and Gold marts.

**Medallion + Dimensional Modelling**
- Medallion stages (Bronze/Silver/Gold) describe data quality progression; dimensional modelling defines how Gold data is organized for analytics. They overlap at Gold, where fact/dimension tables materialize curated domain logic. Silver prepares conformed, but not yet dimensional, datasets consumed by dbt to build dims/facts.

**Business Logic Placement**
- Keep irreversible, finance-approved business rules (e.g., revenue recognition, SCD Type 2 history) inside Gold so they are versioned and testable. Semantic layers (e.g., dbt Semantic Layer or Power BI datasets) should contain lightweight calculations, metrics definitions, and user-centric naming. Never embed row-level masking or security filters solely in Semantic; enforce them in Snowflake (Gold) via row access policies/masking to guarantee enforcement across tools.

**Historical Accuracy vs Real-Time Adjustments**
- Silver holds near-real-time cleansed events (micro-batches every few minutes). Gold runs hourly to rebuild facts/dims that require full history. The Semantic layer (Power BI/Looker) stores dynamic measures (e.g., adjustable attribution windows) by combining Gold facts with Silver delta tables through hybrid models or DirectQuery-on-Spark connectors. Gold exposes parameter-ready aggregate tables; Semantic applies sliding-window filters without mutating the base facts.

## 4. Security & Governance
- **Data in Transit/At Rest:** Blob Storage enforces customer-managed keys; HTTPS/TLS 1.2+ required for all transfers. Snowflake stages use signed URLs with short-lived SAS tokens. Files decrypted only within isolated compute, written onto encrypted ephemeral disks, then wiped post-run. dbt containers pull secrets at runtime from AKV via managed identity.
- **Access Management:** Azure resources use RBAC with least privilege. Airflow’s managed identity has `Storage Blob Data Reader` on landing and `Key Vault Secrets User` to unwrap keys. Snowflake connectivity uses key-pair auth; private connectivity uses Snowflake Azure Privatelink endpoint.
- **Snowflake RBAC:** Separate roles per layer (`RAW_ROLE`, `SILVER_ROLE`, `GOLD_ROLE`, `SEMANTIC_ROLE`) inheriting from a `PIPELINE_ROLE` for Airflow and `ANALYST_ROLE` for BI. Row access policies + dynamic data masking on sensitive columns (PII) ensure analysts only see tokenized data. Future grants automation ensures new tables inherit privileges.

## 5. Operational Considerations
- **Monitoring:** Airflow task metrics exported to Azure Monitor; set alerts on DAG SLA misses. Snowflake QUERY_HISTORY feeds into Datadog for warehouse cost/latency tracking. Blob Storage diagnostic logs capture FileSensor lag.
- **Testing & Deployment:** dbt CI runs on pull requests (`dbt build --select state:modified+ test_type:generic`). Terraform manages infrastructure definitions in `baseline/` and `infra/`. Airflow DAGs deployed via GitOps (e.g., helm chart). Integration tests decrypt sample fixtures and validate end-to-end load in a staging Snowflake account.
- **Schema Changes & Data Quality:** Enforce contracts with dbt `sources` and schema tests; Airflow watchers validate expected columns via Great Expectations before Snowflake load. Backfill scripts regenerate Silver/Gold tables using dbt snapshots if schema drift occurs. Data quality failures mark the DAG as failed, quarantine the file, and notify Slack/Teams.
- **Failure Handling:** Each DAG task writes checkpoints to a control table; retries have exponential backoff. If decryption fails, move blob to `landing/error/` and raise a PagerDuty incident. If Snowflake copy fails, the transaction rolls back; Airflow task clears partial loads before re-run.
