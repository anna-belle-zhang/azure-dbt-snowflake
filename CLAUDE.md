# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a DBT (data build tool) project that runs on Azure Container Instances (ACI) and connects to Snowflake for data transformations. The architecture uses GitHub Actions for CI/CD, Azure Container Registry (ACR) for image storage, and Terraform for infrastructure as code.

## Architecture

**Two-tier Infrastructure Deployment:**
- `baseline/`: Core infrastructure (Resource Group, ACR, Key Vault) - deployed once
- `infra/`: Application infrastructure (ACI) - deployed on every code change

**Data Pipeline:**
- DBT runs in ACI containers triggered by GitHub Actions on push to main
- Snowflake credentials stored in Azure Key Vault as base64-encoded certificate
- Container uses managed identity to retrieve secrets from Key Vault at runtime
- DBT pushes transformations to Snowflake (compute happens in Snowflake, not ACI)

**DBT Model Structure:**
- `staging/`: Views that clean and select fields from source tables (TPCH dataset: customer, orders)
- `intermediate/`: Tables with business logic and joins between staging models
- Target database: `DBT_MODELS` in Snowflake with schemas `staging` and `intermediate`

## Common Commands

### DBT Development

```bash
# Run DBT locally (development profile)
cd tpch_transform
dbt run

# Run with production profile
dbt run -t pro

# Run specific model
dbt run --select model_name

# Test models
dbt test

# Clean build artifacts
dbt clean
```

### Docker Operations

```bash
# Build image locally
cd tpch_transform
make build

# Build with custom version
make build DOCKER_VERSION=v1.0.0

# Push to registry (requires ACR login)
make push
```

### Terraform Deployment

```bash
# Deploy baseline infrastructure (one-time)
cd baseline
terraform init
terraform plan
terraform apply

# Deploy application infrastructure
cd infra
terraform init
terraform plan
terraform apply -auto-approve -var='image_version=<commit-sha>'
```

### GitHub Secrets Required

- `AZURE_CREDENTIALS`: Azure service principal credentials
- `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`
- `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`: ACR credentials

## Key Configuration Files

**profiles.yml**: Two environments
- `dev`: Local development using `~/.ssh/snowflake_dbt.p8`
- `pro`: Production using `/snowflake_dbt.pem` (retrieved from Key Vault)

**dbt_project.yml**: Model materialization
- Staging models → views
- Intermediate models → tables with documentation persistence

**entrypoint.sh**: Container startup sequence
1. Retrieve OAuth token from Azure Instance Metadata Service
2. Fetch Snowflake certificate from Key Vault using token
3. Decode base64 certificate to PEM format
4. Execute `dbt run -t pro`

## Important Architecture Notes

**State Management:**
- Terraform remote state stored in Azure Storage Account
- `infra/` references `baseline/` state via `terraform_remote_state` data source
- State files: `dbt_baseline.terraform.tfstate` and `dbt_infra.terraform.tfstate`

**Container Restart Policy:**
- ACI configured with `restart_policy = "Never"` - containers run once and stop
- Each deployment triggers a new container execution
- Image tag uses commit SHA for version tracking

**Secret Management:**
- Snowflake certificate stored in Key Vault as `snowflake-certificate` secret (base64 encoded)
- ACI uses SystemAssigned managed identity with "Key Vault Secrets User" role
- Environment variables: `ENV_KV_URL`, `ENV_SNOW_SECRET`

## DBT Model Conventions

**Naming:**
- Staging: `stg_<source_name>.sql` (e.g., `stg_customers.sql`)
- Intermediate: `int_<business_concept>.sql` (e.g., `int_customers.sql`)

**References:**
- Source tables: `{{ source('tpch', 'customer') }}`
- Staging models: `{{ ref('stg_customers') }}`

**Schema Files:**
- `stg_sources.yaml`: Defines source table connections
- `schema.yml`: Documents model columns and tests

## CI/CD Workflow

On push to main branch:
1. Build Docker image with commit SHA tag
2. Push to `dbtjobs.azurecr.io/dbt/tpch_transform:<sha>`
3. Run Terraform apply in `infra/` with `image_version` variable
4. ACI deploys new container and executes DBT transformations immediately

## Snowflake Configuration

**Required Setup:**
- Database: `DBT_MODELS`
- Schemas: `staging`, `intermediate`
- Warehouse: `COMPUTE_WH`
- Authentication: RSA key pair (not password-based)
- Source data: `tpch_sf1` dataset (customer, orders tables)

**Certificate Generation:**
Follow Snowflake's key-pair authentication guide, then:
```bash
# Convert private key to base64 for Key Vault
base64 -i snowflake_dbt.p8
```

## Working with This Repository

**Adding New Models:**
1. Create SQL file in `models/staging/` or `models/intermediate/`
2. Update corresponding `schema.yml` with documentation
3. Test locally with `dbt run --select model_name`
4. Commit and push to trigger CI/CD pipeline

**Infrastructure Changes:**
- Baseline changes (ACR, Key Vault): modify `baseline/` and apply separately
- Application changes (ACI config): modify `infra/` - automatically applied via GitHub Actions

**Hardcoded Values to Update for New Deployments:**
- ACR name: `dbtjobs` (must be globally unique)
- Key Vault name: `secrets-aci` (must be globally unique)
- Snowflake account: `so85363.west-europe.azure`
- Resource group names and storage account in backend configurations
