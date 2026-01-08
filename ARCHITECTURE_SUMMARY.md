# Architecture Design Summary

## Overview

This repository now contains a comprehensive, audit-ready data pipeline architecture designed for Australian financial services compliance (APRA CPS 230/234/235, Privacy Act, ASIC).

## What Was Created

### 1. **ARCHITECTURE.md** (1,500+ lines)
Complete technical architecture document covering:

#### Section 1: Regulatory Compliance Framework
- Executive summary emphasizing "regulatory certainty"
- Six core audit questions and architectural responses
- APRA/Privacy Act/ASIC compliance mapping

#### Section 2: End-to-End Pipeline Architecture
- Azure Blob Storage → Airflow → Decrypt → Snowflake → dbt → BI
- Detailed component integration (Azure Function, Key Vault, Snowflake stages)
- Step-by-step data flow with security controls

#### Section 3: Lakehouse Architecture & Dimensional Modeling
- Real-world example: JSON logs → dimensional model
- Bronze/Silver/Gold/Semantic layer responsibilities
- When to use Gold vs Semantic layer (with examples)
- Hybrid real-time + historical architecture

#### Section 4: Security and Governance
- Encryption in transit and at rest
- Azure to Snowflake integration via managed identity
- Comprehensive Snowflake RBAC model with examples
- PII masking and row-level security

#### Section 5: Control Plane (Implicit Conditions)
- **9 implicit conditions** for production readiness:
  1. Data Sensitivity & Minimal Exposure
  2. Idempotency & Duplicate Handling
  3. Time Semantics (Event Time vs Process Time)
  4. Failure Modes & Recovery
  5. Auditability & Reproducibility
  6. Key & Secret Management
  7. Access Control & Governance
  8. Schema Evolution & Change Management
  9. Operational Observability
- Each condition includes: question, controls, compliance mapping, implementation

#### Section 6: Architecture Diagrams
- Reference to Mermaid diagrams (data plane + control plane)

#### Section 7: Operational Considerations
- Monitoring (Airflow, dbt, Snowflake)
- Testing (unit, integration, end-to-end)
- Deployment (CI/CD, blue-green)
- Failure handling (schema changes, data quality, pipeline failures)
- Performance optimization (clustering, materialized views, incremental models)

#### Section 8: Implementation Roadmap
- 4-phase plan (8 weeks)

### 2. **INTERVIEW_GUIDE.md**
Concise interview preparation guide:

- **30-second elevator pitch**
- **3-minute walkthrough** (data plane + control plane + audit questions)
- **Key differentiators** (what makes this senior/lead level)
- **6 common follow-up questions** with detailed answers:
  - Key compromise scenario
  - dbt bug in production
  - Accidental PII access
  - Late-arriving data
  - Multi-source scalability
  - Cost at scale
- **Whiteboard drawing tips**
- **Closing statement**
- **Pre-interview checklist**

### 3. **diagrams/data-plane.mmd**
Mermaid flowchart showing:
- Azure components (Blob Storage, Key Vault, Airflow, Azure Function)
- Snowflake layers (Stage → RAW → SILVER → GOLD → SEMANTIC → BI)
- Quarantine zone for failed records
- Security boundaries and data flow

### 4. **diagrams/control-plane.mmd**
Mermaid diagram mapping:
- 9 implicit conditions (yellow boxes)
- Pipeline components where they apply (blue boxes)
- Visual representation of "control plane thinking"

### 5. **diagrams/README.md**
Guide for viewing and using diagrams:
- Viewing options (GitHub, Mermaid Live, VS Code, export to PNG/SVG)
- Whiteboard simplification tips
- Interview usage guide
- Color legend

## Key Architectural Principles

### 1. Regulatory Compliance First
- Not "how do we add compliance later" but "compliance drives design"
- APRA CPS 230/234/235, Privacy Act, ASIC requirements **embedded** into platform

### 2. Control Plane Thinking
- Recognizing implicit conditions that requirements don't specify
- Proactive design for idempotency, time semantics, failure recovery
- "Can it run?" ≠ "Can it pass audit and survive production?"

### 3. Layered Immutability
- **Bronze**: Raw, immutable, append-only (source of truth)
- **Silver**: Cleaned, traceable to Bronze
- **Gold**: Dimensional models (facts/dimensions), versioned
- **Semantic**: Metrics, never mutates history

### 4. Security by Design
- **Minimal plaintext exposure**: Decryption only in secure boundary, TTL enforced
- **System-enforced controls**: RBAC + masking (not user awareness)
- **Key management**: Azure Key Vault with managed identity, no secrets in code
- **Auditability**: Every operation traceable via batch_id + dbt_git_sha + event_time

### 5. Reproducibility & Explainability
- Can answer: "How was this number calculated 12 months ago?"
- Version tracking: Git SHA for dbt models, batch_id for data loads
- Lineage: dbt automatically generates DAG and column-level lineage
- Comparison: Can diff old vs new transformations

## How to Use This Architecture

### For Interviews
1. Start with **INTERVIEW_GUIDE.md** for quick prep
2. Reference **ARCHITECTURE.md** for deep dives
3. Use **diagrams** for visual explanation
4. Practice 30-second pitch and 3-minute walkthrough

### For Implementation
1. Follow **Implementation Roadmap** (Section 7 of ARCHITECTURE.md)
2. Use code examples as templates (SQL, Python, YAML throughout)
3. Reference **Security and Governance** section for RBAC setup
4. Apply **Control Plane conditions** as checklists for each component

### For Documentation
1. **CLAUDE.md** already exists (repository working guide)
2. **ARCHITECTURE.md** serves as technical design doc
3. **diagrams/** can be exported to PNG for presentations
4. Code snippets are production-ready, not pseudocode

## Compliance Checklist

| Regulation | Requirement | Architecture Section | Status |
|------------|-------------|---------------------|--------|
| **APRA CPS 234** | Information asset protection | Section 4.1 (Encryption) | ✅ |
| **APRA CPS 234** | Access control & audit | Section 4.3 (RBAC) | ✅ |
| **APRA CPS 230** | Operational risk management | Section 5 (Control Plane) | ✅ |
| **APRA CPS 235** | Data risk & quality | Section 3.4 (Data Governance) | ✅ |
| **Privacy Act 1988** | Minimal data exposure | Section 5.1.1 (Data Sensitivity) | ✅ |
| **ASIC Reporting** | Data explainability | Section 5.1.5 (Auditability) | ✅ |

## Technical Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Orchestration** | Apache Airflow (AKS/VM) | DAG scheduling, file detection, failure handling |
| **Decryption** | Azure Functions (Python) | Secure compute boundary, managed identity |
| **Key Management** | Azure Key Vault | CMK storage, secret management, rotation |
| **Storage** | Azure Blob Storage | Encrypted Parquet landing zone, staging |
| **Data Warehouse** | Snowflake | Bronze/Silver/Gold/Semantic layers |
| **Transformation** | dbt Core | SQL-based transformations, version control |
| **BI** | Power BI / Tableau | Governed consumption via Semantic layer |
| **CI/CD** | GitHub Actions | Automated testing, deployment |
| **Monitoring** | Airflow + Snowflake + Azure Monitor | SLA, data quality, cost tracking |

## File Structure

```
azure-dbt-snowflake/
├── ARCHITECTURE.md              # Complete technical architecture (1500+ lines)
├── ARCHITECTURE_SUMMARY.md      # This file (executive summary)
├── INTERVIEW_GUIDE.md           # Interview prep guide
├── CLAUDE.md                    # Repository working guide
├── diagrams/
│   ├── README.md               # Diagram viewing guide
│   ├── data-plane.mmd          # End-to-end pipeline (Mermaid)
│   └── control-plane.mmd       # Implicit conditions (Mermaid)
├── baseline/                    # Terraform for baseline infra (existing)
├── infra/                       # Terraform for app infra (existing)
├── tpch_transform/             # Existing dbt project (example)
└── newrequirement.md           # Original requirements (reference)
```

## What Makes This Architecture "Audit-Ready"

### Not Just Technically Sound, But:

1. **Addresses auditor questions directly** (6 core questions in Section 1.2)
2. **Maps to specific regulations** (APRA CPS 230/234/235, Privacy Act, ASIC)
3. **Implements control plane** (9 implicit conditions beyond functional requirements)
4. **Embeds compliance in platform** (not bolt-on, but default behavior)
5. **Provides reproducibility** (batch_id + dbt_git_sha + event_time = explainability)
6. **Separates concerns** (Bronze/Silver/Gold/Semantic with clear responsibilities)
7. **System-enforced security** (RBAC + masking, not user "carefulness")

### Interview Positioning

> "This architecture passes audit because it transforms **engineering certainty** into **regulatory certainty**. Encryption, access control, lineage, and reproducibility are not add-ons—they're **default behaviors of the platform**."

## Next Steps

1. **For Interview Prep**: Read INTERVIEW_GUIDE.md, practice walkthrough
2. **For Implementation**: Follow roadmap in ARCHITECTURE.md Section 7
3. **For Team Presentation**: Export diagrams to PNG, use ARCHITECTURE.md as slide deck outline
4. **For Audit Submission**: Use Section 1.2 (6 audit questions) as compliance narrative

---

**Created**: 2026-01-06
**Purpose**: Australian financial services data pipeline architecture
**Compliance**: APRA CPS 230/234/235, Privacy Act 1988, ASIC
**Status**: Ready for interview presentation and implementation
