# dbt_local Review (newclearify.md Lens)

## Scope & Approach
- Reviewed `local_test/dbt_local` to determine how well the local dbt project demonstrates the “regulatory-by-default” controls described in `newclearify.md`.
- Focused on the control plane themes called out in the memo: minimal exposure, access traceability, tamper detection, reproducibility, RBAC/masking, idempotency, time semantics, and failure isolation.
- Evidence comes from the committed SQL/Jinja, YAML, and profile files; runtime behaviour (Airflow, encryption scripts) was considered out of scope except where referenced from dbt.

## Control Coverage Snapshot
| Regulatory control (per newclearify.md) | Evidence in `dbt_local` | Gaps / Risk | Verdict |
| --- | --- | --- | --- |
| **Layering & lineage** (Bronze → Silver → Gold → Semantic) | Clearly modelled in `dbt_project.yml` with tags + metadata. | Bronze models query physical tables instead of dbt `source()` definitions, so lineage artifacts omit the raw landing zone + file controls. | ⚠️ Partial |
| **Idempotency & traceability** (`batch_id`, `rule_version`, file hash) | `batch_id` / `execution_date` vars propagate through most models. | No file hash, rule version, or run control tables; bronze objects can be updated instead of immutable append-only loads. | ⚠️ Partial |
| **Data quality & quarantine** | `silver_*` models include DQ flags and dedupe logic. | Invalid records (e.g., negative order_amount) are filtered out before they can be flagged or quarantined, so issues become silent drops. | ⚠️ Partial |
| **Access control & masking** | None inside dbt; schemas expose every PII column. | Contradicts “least exposure” and “masking default” guidance; no row/column policies or semantic-only PII views. | ❌ Missing |
| **Auditability & reproducibility** | Tags, `persist_docs`, and batch metadata exist; `semantic` views express KPI logic. | Build currently fails (`fct_orders` references non-existent columns; `dbt_utils` package missing); without a successful run, lineage/artifacts cannot defend audit questions. | ❌ Missing |

## Detailed Findings & Recommendations

### 1. Semantic models fail because `fct_orders` is broken
- `models/gold/fct_orders.sql` selects `o.customer_segment`, `o.country`, and `o.ingested_at` from `silver_orders`, but those columns do not exist (`silver_orders.sql` provides only order attributes and metadata). `models/semantic/order_metrics.sql` depends on this table (`ref("fct_orders")`).
- Result: `dbt build` cannot succeed, meaning Airflow runs and audit replays cannot reach the Semantic layer—directly violating the “business logic is auditable asset” tenet.
- **Action:** Decide whether `fact_orders.sql` or `fct_orders.sql` is the authoritative fact table. Drop the redundant model or update `silver_orders` to join `silver_customers` so the requested columns exist, then point Semantic models to the surviving fact.

### 2. Bronze models bypass dbt `source()` definitions
- `bronze_customers.sql` and `bronze_orders.sql` select straight from `nocodb_db.src_*` (lines 8-22 and 8-21), even though `models/bronze/schema.yml` and `models/schema.yml` define named sources.
- Without `source()` calls, dbt lineage cannot show the encrypted Parquet landing zone, file hash validation, or the Airflow ingestion contract that newclearify positions as the primary audit control.
- **Action:** Replace the direct table references with `{{ source('parquet_files', 'customers') }}` (or the correct `landing` source), add source freshness tests, and persist landing metadata (file hash, decrypt timestamp) in bronze tables.

### 3. Metadata stops at `batch_id` / `execution_date`
- `dbt_project.yml` injects batch metadata, but there is no notion of `rule_version`, `file_hash`, `control_table`, or `run_id` columns in the bronze/silver/gold models.
- This makes it impossible to answer “Which file hash + rule version produced this row?”—one of the six questions listed in newclearify.
- **Action:** Introduce macros to stamp `rule_version` (e.g., git SHA of the model), `file_hash`, and Airflow `run_id`. Persist them through all layers and materialize a lightweight control table keyed by `batch_id` that dbt (or Airflow) updates with status, counts, and hashes.

### 4. Invalid data is discarded instead of quarantined
- In `silver_orders.sql` lines 31-45, the model labels negative or suspicious amounts via `data_quality_flag`, but the `source` CTE already filters `order_amount >= 0`, so the “negative_amount” branch can never fire. The invalid records simply disappear.
- This conflicts with the memo’s emphasis on “quarantine zone” and “failure isolation”. Auditors expect a reproducible record of what was rejected and why.
- **Action:** Remove the hard filter, persist problematic rows (e.g., `WHERE data_quality_flag IS NULL` only when feeding `fact_orders`), and/or materialize a `silver_orders_quarantine` model keyed by `batch_id` + `order_id` with the rejection reason.

### 5. Tests rely on `dbt_utils`, but the package is absent
- `models/silver/schema.yml` uses `dbt_utils.unique_combination_of_columns`, yet there is no `packages.yml` under `dbt_local`. Running `dbt deps` therefore fails, blocking every build.
- Missing packages break the “system guarantees accuracy” pillar from CPS 235.
- **Action:** Add a `packages.yml` alongside `dbt_project.yml` (e.g., `packages: - package: dbt-labs/dbt_utils version: 1.0.0`), document `dbt deps` in `local_test/RUN_TEST.md`, and consider adding other governance packages (`audit_helper`, `elementary`).

### 6. Sensitive columns are exposed in every schema
- PII columns (email, phone, first/last name) propagate from bronze through gold to semantic without masking, and all schemas are given database-level access in `dbt_project.yml`.
- newclearify explicitly calls out Snowflake RBAC, masking, and row access policies as non-negotiable audit controls.
- **Action:** Even in MySQL, simulate the policies by segregating schemas (e.g., keep `email/phone` only in bronze/silver, publish masked versions in semantic), add column-level masking macros, and document the RBAC intent so it can be ported to Snowflake.

### 7. Secrets live in `profiles.yml`
- The sample profile hardcodes the `nocodb` username/password defaults; the memo stresses that secrets must sit in Key Vault or CI variables, not in code.
- **Action:** Replace the defaults with placeholder environment variables (e.g., `{{ env_var('LOCAL_MYSQL_PASSWORD') }}` without a literal fallback), and document how Airflow injects credentials via `.env` or Docker secrets.

### 8. Time semantics are underspecified
- `silver_orders` rewrites `order_date` / `order_timestamp` via `STR_TO_DATE` but drops timezone information, and there is no `process_time` column separate from the event timestamps. Late-arriving logic is also missing.
- Without explicit time semantics, it is impossible to answer “When did this record become effective?” which the memo lists as an implicit constraint.
- **Action:** Persist both `event_time` (source timestamp) and `ingestion_time` (dbt run start). Add logic/macros for late-arriving handling (e.g., `valid_from`, `valid_to`, `is_late` flags) and tests that guard against regressions.

## Strengths Worth Preserving
- Clear four-layer folder structure with consistent tags and `+persist_docs`, which helps make business logic visible to auditors.
- `silver_*` models already capture useful metadata (`data_quality_flag`, `transformation_timestamp`) that can seed the quarantine + audit trail story.
- `tests/test_negative_order_amounts.sql` shows the intent to externalize business-rule tests under `tests/`, matching the memo’s recommendation for complex validations.

## Suggested Next Steps
1. Fix the failing models/packages so `dbt build` succeeds end-to-end (controls have no credibility until the pipeline runs cleanly).
2. Introduce landing-source metadata (`source()` usage, hashes, rule versions) and propagate it through every layer to answer the six audit questions verbatim.
3. Build explicit quarantine outputs and retention policies so invalid data is auditable rather than silently dropped.
4. Simulate RBAC/masking even in the local MySQL target to rehearse the Snowflake policies mandated in newclearify.
5. Document the credential management and time-semantics decisions inside this folder so the local environment mirrors the compliance expectations during interviews or audits.
