# Interview Guide: Data Pipeline Architecture

## Quick Reference for Architecture Presentation

### 30-Second Elevator Pitch

> "This architecture passes audit not because of any single tool, but because it **embeds regulatory expectations directly into the data lifecycle**. Encryption, access control, lineage, and reproducibility are not bolt-ons—they're **default behaviors of the platform**. That's what allows us to scale data usage without increasing regulatory risk."

---

## Interview Walkthrough (3 Minutes)

### 1. Data Plane Overview (60 seconds)

**Flow**:
1. **Azure Blob Storage** receives encrypted Parquet files
2. **Airflow** detects file and validates (checksum, naming)
3. **Azure Function** decrypts in secure compute boundary using **Key Vault** (managed identity)
4. **Decrypted file** staged temporarily (TTL enforced, no long-lived plaintext)
5. **Snowflake COPY INTO** loads to **Bronze** layer (immutable, raw)
6. **dbt** transforms through layers:
   - **Silver**: Cleaned, standardized
   - **Gold**: Dimensional models (facts/dimensions)
   - **Semantic**: Business metrics
7. **BI Layer** consumes governed data

**Diagram**: Show `diagrams/data-plane.mmd`

### 2. Control Plane (Implicit Conditions) (90 seconds)

> "Beyond file size, the design is driven by **implicit constraints** that determine whether it can pass audit and survive production."

**Nine Implicit Conditions**:

| # | Condition | Key Controls | Compliance |
|---|-----------|--------------|------------|
| 1 | **Data Sensitivity** | Key Vault, Masking, TTL | Privacy Act + CPS 234 |
| 2 | **Idempotency** | file_hash, batch_id, deduplication | Production reliability |
| 3 | **Time Semantics** | event_time vs process_time | Historical accuracy |
| 4 | **Failure Recovery** | Quarantine, immutable Bronze, replay | CPS 230 (Operational Risk) |
| 5 | **Auditability** | Lineage, Git versioning, access history | ASIC + APRA reproducibility |
| 6 | **Key Management** | Key Vault, managed identity, rotation | CPS 234 (Security) |
| 7 | **Access Governance** | RBAC, masking, row policies | Privacy Act + CPS 234 |
| 8 | **Schema Evolution** | on_schema_change, contracts | Production stability |
| 9 | **Observability** | SLA, tests, freshness, cost monitoring | CPS 230 (Resilience) |

**Diagram**: Show `diagrams/control-plane.mmd`

**Key Point**: *"Each condition is attached to specific pipeline stages—not theoretical, but implemented."*

### 3. Why This Architecture Passes Audit (30 seconds)

**Six Audit Questions Answered**:

1. ✅ **"Where does plaintext exist?"** → Only in controlled compute, short-lived, never in logs
2. ✅ **"Is Airflow/dbt audit-friendly?"** → Execution history + versioned logic = audit assets
3. ✅ **"How prevent tampering?"** → Bronze immutable, layers traceable, can recalculate
4. ✅ **"How enforce least privilege?"** → System-enforced RBAC/masking, not user awareness
5. ✅ **"Can you explain old numbers?"** → batch_id + dbt_git_sha + event_time = reproducible
6. ✅ **"What if logic changes?"** → Gold versioned, Semantic never rewrites history

---

## Key Differentiators (What Makes This Senior/Lead Level)

### 1. **Regulatory Compliance as First-Class Concern**
- Not "can we add compliance later?" but "compliance drives design"
- APRA CPS 230/234/235, Privacy Act, ASIC requirements explicitly addressed

### 2. **Control Plane Thinking**
- Recognizing "implicit conditions" that requirements don't specify
- Proactively designing for idempotency, time semantics, failure modes

### 3. **Layered Architecture with Clear Responsibilities**
- Bronze: Immutable source of truth
- Silver: Cleaned, standardized
- Gold: Business facts (dimensional models)
- Semantic: Metrics (never mutates history)

### 4. **Separation of "Can Run" vs "Can Survive Production"**
- Technical feasibility ≠ production readiness
- Audit compliance ≠ just encryption
- Operational resilience ≠ just monitoring

---

## Common Follow-Up Questions & Answers

### Q1: "What if the decryption key is compromised?"

**Answer**:
- **Key rotation**: Azure Key Vault supports automated rotation
- **Access logs**: All Key Vault access logged to Azure Monitor
- **Limited blast radius**: Decrypted files are short-lived (TTL), not archived
- **Audit trail**: `batch_id` + `run_id` identifies which data was decrypted with which key version

### Q2: "What if a dbt model has a bug and wrong data is already in production?"

**Answer**:
- **Version tracking**: Every transformation tagged with `dbt_git_sha`
- **Impact assessment**: Lineage graph shows downstream dependencies
- **Recalculation**: Can reprocess from Bronze layer with corrected logic
- **Comparison**: Old vs new results can be diffed by `batch_id` and `dbt_model_version`

**Implementation**:
```sql
-- Compare old vs new transformation results
SELECT
  old.customer_id,
  old.total_orders AS old_total,
  new.total_orders AS new_total,
  new.total_orders - old.total_orders AS difference
FROM gold.fact_customers_v1 old
JOIN gold.fact_customers_v2 new USING (customer_id)
WHERE old.total_orders != new.total_orders;
```

### Q3: "What if an analyst accidentally queries PII?"

**Answer**:
- **Masking by default**: PII columns automatically redacted unless role has explicit privilege
- **Access history**: Snowflake `QUERY_HISTORY` captures all access attempts
- **Row-level security**: Analysts can only see data for their business unit
- **Semantic layer**: Most analysts query pre-aggregated metrics, not raw tables

**Example**:
```sql
-- Masking policy applied to email column
CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() = 'DATA_ENGINEER_ROLE' THEN val
    WHEN CURRENT_ROLE() = 'DATA_ANALYST_ROLE' THEN REGEXP_REPLACE(val, '^(.{2}).*(@.*)$', '\\1***\\2')
    ELSE '***@***.com'
  END;

ALTER TABLE gold.dim_customers
  MODIFY COLUMN email SET MASKING POLICY email_mask;
```

### Q4: "How do you handle late-arriving data?"

**Answer**:
- **Separate time semantics**: `event_time` (business) vs `process_time` (ingestion)
- **Incremental processing**: Silver/Gold models use `event_time` for logic
- **Backfill strategy**: Can reprocess historical dates without affecting current data
- **Late-arrival tolerance**: Configurable window (e.g., accept data up to 7 days late)

**Implementation**:
```sql
-- Silver model handles late arrivals
{{ config(
    materialized='incremental',
    unique_key='event_id'
) }}

SELECT
  event_id,
  event_timestamp,  -- Business time (when event occurred)
  CURRENT_TIMESTAMP() AS ingestion_timestamp  -- Process time
FROM {{ source('bronze', 'raw_events') }}

{% if is_incremental() %}
  -- Process events from last 7 days (handles late arrivals)
  WHERE event_timestamp >= DATEADD(day, -7, CURRENT_DATE())
{% endif %}
```

### Q5: "How does this scale to multiple data sources?"

**Answer**:
- **Modular design**: Each data source gets its own Airflow DAG + dbt project
- **Shared infrastructure**: Common Key Vault, Snowflake instance, monitoring
- **Reusable patterns**: Decryption function templated, dbt macros shared
- **Isolated failures**: One source failing doesn't block others

**Example**:
```
dbt_projects/
├── customer_data/          # TPCH customer pipeline
├── transaction_data/       # Financial transactions
├── clickstream_data/       # Web events
└── shared/
    ├── macros/             # Common dbt macros
    └── packages/           # Shared dbt packages
```

### Q6: "What's the cost of running this at scale?"

**Answer**:
- **Azure costs**:
  - Blob Storage: ~$0.02/GB/month (encrypted at rest)
  - Key Vault: ~$0.03/10,000 operations
  - Azure Functions: ~$0.20/million executions (consumption plan)
- **Snowflake costs**:
  - Storage: ~$40/TB/month (compressed)
  - Compute: Warehouses can auto-suspend (credits charged by second)
  - Separate warehouses by workload (ingestion/transform/analytics)
- **Cost optimization**:
  - Incremental dbt models (only process new data)
  - Clustering on frequently filtered columns
  - Materialized views for expensive aggregations
  - Query result caching

---

## Whiteboard Drawing Tips

### Main Diagram (Data Plane)

1. **Left side**: Azure (Blob Storage, Key Vault, Airflow, Azure Function)
2. **Middle**: Transition (decrypted staging, Snowflake external stage)
3. **Right side**: Snowflake (Bronze → Silver → Gold → Semantic → BI)

**Key annotations**:
- Circle "Secure Compute Boundary" around decryption step
- Arrow "TTL" on decrypted zone
- "Immutable" label on Bronze
- "RBAC + Masking" label on BI layer

### Control Plane (Optional, Advanced)

**Layout**:
- Top: 9 boxes for implicit conditions
- Bottom: Pipeline stages
- Arrows connecting conditions to stages

**Verbal walkthrough**:
> "These 9 conditions aren't afterthoughts—each one is implemented at specific pipeline stages. For example, idempotency (file_hash + batch_id) is enforced at ingestion and Bronze load, while access governance (RBAC + masking) applies across all Snowflake layers."

---

## Closing Statement

> "This architecture passes audit because it transforms **engineering certainty into regulatory certainty**. The tools—Azure, Airflow, dbt, Snowflake—are standard. What's differentiated is how we've embedded compliance, resilience, and auditability into the platform's default behavior, not as add-ons."

---

## Files Reference

| File | Purpose |
|------|---------|
| `ARCHITECTURE.md` | Complete technical architecture (1500+ lines) |
| `diagrams/data-plane.mmd` | Mermaid diagram: End-to-end pipeline |
| `diagrams/control-plane.mmd` | Mermaid diagram: Implicit conditions |
| `INTERVIEW_GUIDE.md` | This file (interview preparation) |
| `CLAUDE.md` | Repository working guide for future sessions |

---

## Pre-Interview Checklist

- [ ] Review 6 audit questions and answers (section 1.2 of ARCHITECTURE.md)
- [ ] Memorize 9 implicit conditions (section 5.1 of ARCHITECTURE.md)
- [ ] Practice 30-second elevator pitch
- [ ] Review Mermaid diagrams (can draw simplified version on whiteboard)
- [ ] Prepare 3 follow-up question responses (Q1-Q6 above)
- [ ] Understand Snowflake RBAC example (section 3.3 of ARCHITECTURE.md)
- [ ] Know Gold vs Semantic layer decision logic (section 2.4 of ARCHITECTURE.md)

**Good luck!**
