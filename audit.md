# Audit Readiness Summary

This document ties the current local test stack (`local_test/`) to the regulatory themes captured in `newclearify.md`, showing how the implementation addresses APRA/Privacy Act expectations and where follow-up work remains.

## 1. Regulatory Questions vs. Local Controls

| Regulator question (per `newclearify.md`) | Local control evidence | Residual gap |
| --- | --- | --- |
| **Where/when does plaintext exist?** | Encrypted Parquet files stay under `local_test/data/encrypted/` until the Airflow DAG runs `scripts/decrypt_parquet.py` inside the container; decrypted files are placed under `local_test/data/decrypted/` temporarily and deleted by `cleanup_decrypted_files`. | No automated TTL enforcement outside DAG (manual runs could leave decrypted files). Key management still uses a local Fernet key file vs. Key Vault. |
| **Who accessed what data and when?** | Airflow DAG captures `run_id`, `execution_date`, and the dbt project injects these as `batch_id`/`execution_date` fields (see `dbt_project.yml:19-22`, `bronze` models). dbt’s compiled artifacts/logs provide lineage for every run. | No centralized audit log beyond dbt/ Airflow logs; Snowflake `ACCESS HISTORY` equivalent is not simulated in MySQL. |
| **Was data tampered with silently?** | `scripts/encrypt_parquet.py` stores `file_hash_sha256` metadata; Bronze models carry batch metadata; Silver models include `data_quality_flag` columns; dbt schema/tests enforce uniqueness, not null, FK checks. | No automated comparison of stored hashes vs. loaded data; quarantine tables exist only conceptually. |
| **Can we replay/recompute historical results?** | Bronze keeps raw change events; `dim_customers_scd2` preserves slowly changing history; Semantic layer `customer_snapshot_daily` provides daily aggregates. Batch metadata + `effective_at` timestamps enable deterministic re-runs. | Need stored control tables (file hash + row counts) to support production-grade replay auditing. |
| **How are keys/permissions managed?** | Airflow DAG loads Fernet keys from `local_test/keys/encryption.key` and ensures secrets are not embedded in dbt models. Profiles use env vars for host/user/password overrides. | Secrets still default to literal passwords; no RBAC/masking simulation on MySQL schemas. |

## 2. Control Walkthrough

1. **Data Generation & Sensitivity (scripts/generate_data.py)**  
   - Synthetic data intentionally includes PII (names, emails, phone) plus embedded quality issues.  
   - Recent updates emit CDC events (insert/update/deactivate) with `effective_at` timestamps, enabling attrition analysis and SCD2 modelling.  
   - Risk: generator still outputs plaintext locally; ensure local disks are treated as dev-only and cleaned after use.

2. **Encryption & Landing (local_test/scripts/encrypt_parquet.py)**  
   - Uses Fernet (AES-128) encryption with per-file metadata (hashes, sizes, timestamp, method).  
   - Fails closed: encrypted files are unreadable as Parquet; metadata persists for audit.  
   - Gap: key storage is a simple file; production must swap for Azure Key Vault with rotation logging.

3. **Airflow DAG (`local_test/airflow/dags/local_encrypted_pipeline.py`)**  
   - Tasks: detect encrypted file → decrypt → load to MySQL → run dbt deps → dbt run/test → cleanup and archive.  
   - Metadata: `run_id` and `ds` flow into dbt vars; `load_to_mysql` now normalizes CDC columns so Bronze schema is guaranteed.  
   - Observability: Subprocess output is logged, but alarms/SLAs are manual. Consider adding Airflow alerts per CPS 230 guidance.

4. **Bronze Layer (dbt)**  
   - `bronze_customers.sql`/`bronze_orders.sql` act as immutable snapshots. CDC fields (`change_type`, `effective_at`) plus `batch_id`/`execution_date` travel downstream.  
   - Tests warn (not fail) on null IDs at this layer, preserving raw fidelity.

5. **Silver Layer**  
   - `silver_customers.sql` dedupes on change timestamp, derives `lifecycle_state`, and flags DQ issues.  
   - `silver_orders.sql` enforces type casting, dedupe, and negative-amount screening.  
   - Both retain ingestion + transformation timestamps for forensic triage.

6. **Gold Layer**  
   - `dim_customers.sql` provides the “current truth” with lifecycle metadata.  
   - `dim_customers_scd2.sql` (new) stores `valid_from`, `valid_to`, `is_current`, enabling reproduction of any past report as demanded by APRA/ASIC.  
   - `fact_orders.sql` and `fct_orders.sql` join customer data with order facts, filtering out DQ failures before metrics consume them.

7. **Semantic Layer / Metrics**  
   - `customer_metrics.sql`, `daily_revenue.sql`, `order_metrics.sql`, and `customer_snapshot_daily.sql` transform curated facts/dims into BI-ready measures.  
   - `customer_snapshot_daily` highlights the attrition story (insert/update/deactivate counts per day) to answer “active population trends” quickly.

## 3. Residual Risks & Next Steps

| Area | Risk | Recommendation |
| --- | --- | --- |
| **Secrets & RBAC** | MySQL credentials default to literal values; schemas are wide-open; masking not simulated. | Use env-only secrets (remove defaults), introduce role-based grants even in MySQL (separate bronze/silver/gold schemas), and simulate masking views. |
| **Control tables & replayability** | File hashes are written but not compared post-load; no control table for row counts / status. | Add a dbt/SQL control table that stores `batch_id`, file hash, expected row count, and load timestamp; compare on each run to detect tampering. |
| **Audit logging** | Airflow/dbt logs exist but are not centralized; no access history equivalent. | Persist DAG metadata (start/end, success/fail, row counts) to a table accessible for audits; simulate Access History by logging SQL statements executed against MySQL. |
| **Automated TTL / cleanup** | `cleanup_decrypted_files` only runs when the DAG succeeds; manual testing can leave plaintext on disk. | Add a cron/task to purge `local_test/data/decrypted` periodically and document operational procedure. |
| **Production parity** | Local stack uses MySQL and local scripts; Snowflake RBAC/masking policies are not enforced here. | Document the mapping (e.g., Bronze schema → Snowflake RAW, MySQL roles → Snowflake roles) and add smoke tests or IaC references showing how the same policies will be applied in Azure/Snowflake. |

## 4. Validation Activity

- `local_test/run_step2.sh` automates RUN_TEST.md Step 2 (data generation + encryption) to ensure testers always start with fresh encrypted files that include CDC signals.  
- dbt: Local CLI currently fails due to the known logbook buffer-size bug; Airflow container runs `dbt deps/run/test` successfully (per prior user run). Until the CLI issue is patched, treat the Airflow execution as the source of truth and record run IDs in audit notes.

## 5. Summary Statement

The current implementation demonstrates the intent outlined in `newclearify.md`: encryption-by-default, layered dbt models with metadata propagation, SCD2 lineage, and metric views designed for auditability. To be production-ready under APRA/Privacy scrutiny, the team must close the remaining gaps around credential storage, RBAC/masking, automated control tables, and centralized logging. Documenting these gaps—and the remediation plan—ensures reviewers from compliance, risk, or audit can trace how engineering controls will satisfy the six key regulatory questions.
