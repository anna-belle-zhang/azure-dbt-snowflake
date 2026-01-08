# Architecture Diagrams

This directory contains Mermaid diagrams for the data pipeline architecture.

## Files

### 1. `data-plane.mmd`
**End-to-End Pipeline (Data Plane)**

Visualizes the complete data flow from encrypted Parquet files in Azure Blob Storage through to BI consumption in Snowflake.

**Key Components**:
- Azure Blob Storage (encrypted landing zone)
- Azure Key Vault (key management)
- Airflow (orchestration)
- Azure Function (secure decryption boundary)
- Quarantine Zone (failed records/files)
- Snowflake (Bronze → Silver → Gold → Semantic → BI)

**Use this diagram to**:
- Explain end-to-end data flow
- Show security controls (encryption, Key Vault, TTL)
- Demonstrate separation of concerns

### 2. `control-plane.mmd`
**Control Plane (Implicit Conditions)**

Maps the 9 implicit conditions (non-functional requirements) to specific pipeline components.

**Nine Implicit Conditions**:
1. Data Sensitivity & Exposure
2. Idempotency & Duplicates
3. Time Semantics
4. Failure Modes & Recovery
5. Auditability & Reproducibility
6. Key & Secret Management
7. Access & Governance
8. Change & Evolution
9. Operational Observability

**Use this diagram to**:
- Show "production-ready" thinking beyond functional requirements
- Explain compliance controls
- Demonstrate senior-level architecture considerations

## Viewing the Diagrams

### Option 1: GitHub (Recommended)
GitHub natively renders Mermaid diagrams. Simply view the `.mmd` files in the GitHub web interface.

### Option 2: Mermaid Live Editor
1. Go to https://mermaid.live/
2. Copy the contents of the `.mmd` file
3. Paste into the editor

### Option 3: VS Code
Install the "Mermaid Preview" extension and open the `.mmd` files.

### Option 4: Export to PNG/SVG
Using Mermaid CLI:
```bash
# Install Mermaid CLI
npm install -g @mermaid-js/mermaid-cli

# Generate PNG
mmdc -i data-plane.mmd -o data-plane.png

# Generate SVG
mmdc -i data-plane.mmd -o data-plane.svg
```

## Whiteboard Simplification

For interview whiteboard sessions, simplify to:

### Data Plane (Simplified)
```
[Azure Blob]  →  [Airflow]  →  [Decrypt (Key Vault)]  →  [Snowflake Stage]
                                                              ↓
                                          [Bronze → Silver → Gold → Semantic → BI]
```

**Key annotations**:
- Circle "Secure Boundary" around decrypt step
- Label "Immutable" on Bronze
- Label "RBAC + Masking" on BI

### Control Plane (Simplified)
```
Implicit Conditions:
1. Security    → Key Vault, Masking
2. Idempotency → file_hash, batch_id
3. Time        → event_time vs process_time
4. Recovery    → Quarantine, replay
5. Audit       → Lineage, versioning
...
```

Point to specific pipeline stages where each applies.

## Interview Tips

1. **Start with Data Plane**: Show the "happy path" data flow
2. **Then introduce Control Plane**: Explain "here's what makes it production-ready"
3. **Pick 3-4 conditions to deep-dive**: Don't try to explain all 9 in detail
4. **Use real examples**: Reference APRA CPS 234, Privacy Act to show regulatory awareness

## Color Legend

### Data Plane Diagram
- **Blue (#0078D4)**: Azure components
- **Light Blue (#29B5E8)**: Snowflake components
- **Red (#FF6B6B)**: Security/Quarantine
- **Green (#51CF66)**: Compute boundaries

### Control Plane Diagram
- **Yellow (#FFF3BF)**: Implicit conditions (requirements)
- **Light Blue (#D0EBFF)**: Pipeline components (implementation)

---

For complete architecture details, see `../ARCHITECTURE.md`.
For interview preparation, see `../INTERVIEW_GUIDE.md`.
