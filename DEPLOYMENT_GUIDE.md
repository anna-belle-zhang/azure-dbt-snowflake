# Trunk-Based Development Deployment Guide

## Overview

This repository implements trunk-based development with environment-locked release configurations for two environments: **dev** and **uat** (production environment removed).

## Architecture Summary

### Environments
- **DEV**: Development environment (auto-deploy on every push to main)
- **UAT**: User Acceptance Testing (manual deploy via git tags)
- ~~**PRD**: Production (disabled/archived)~~

### Key Components
1. **Release Configs**: `release/dev.yaml`, `release/uat.yaml`
2. **CI/CD Workflows**: `.github/workflows/deploy-dev.yml`, `deploy-uat.yml`
3. **Terraform**: Environment-specific configurations in `baseline-{env}/` and `infra-{env}/`
4. **DBT**: Parameterized profiles for dev/uat in `tpch_transform/profiles.yml`
5. **Managed Identities**: User-assigned identities for ACI containers

## Prerequisites

### Azure Resources (Already Created)
- ✅ Resource Groups (dev, uat)
- ✅ Storage Accounts (Terraform state)
- ✅ Container Registries (ACR)
- ✅ Key Vaults
- ✅ Service Principal for GitHub Actions
- ✅ User-assigned Managed Identities for ACI

### Required Tools
- Azure CLI (`az`)
- GitHub CLI (`gh`)
- Terraform (v1.2.9+)
- yq (YAML processor)
- OpenSSL (for Snowflake keys)

### Credentials
- Azure Subscription: ddfe89b6-c4e5-4d13-a3c0-441f618f19f7 (Blackwoods Australia)
- GitHub access with workflow permissions
- Snowflake admin access for dev and uat accounts

## Step-by-Step Deployment

### Phase 1: Setup Managed Identities and GitHub Integration

#### 1.1 Create Managed Identities and Service Principal

```bash
# Run the managed identity setup script
./scripts/setup-managed-identities.sh
```

This creates:
- Service Principal for GitHub Actions
- User-assigned managed identities for dev and uat ACI containers
- RBAC roles for Key Vault access

#### 1.2 Configure GitHub Secrets

Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/secrets/actions`

Add these repository secrets (values from setup-managed-identities.sh output):

```
AZURE_CREDENTIALS=<entire JSON from script output>
AZURE_CLIENT_ID=<from script>
AZURE_CLIENT_SECRET=<from script>
AZURE_SUBSCRIPTION_ID=ddfe89b6-c4e5-4d13-a3c0-441f618f19f7
AZURE_TENANT_ID=<from script>
```

Get ACR credentials:
```bash
az acr credential show --name dbtjobsdev
az acr credential show --name dbtjobsuat
```

Add as secrets:
```
REGISTRY_USERNAME_DEV=<from above>
REGISTRY_PASSWORD_DEV=<from above>
REGISTRY_USERNAME_UAT=<from above>
REGISTRY_PASSWORD_UAT=<from above>
```

#### 1.3 Create GitHub Environments

Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/environments`

Create two environments:

**dev:**
- No protection rules (auto-deploy)

**uat:**
- ✅ Required reviewers: 1 person
- ✅ Deployment branches: Only tags matching `rel-*-uat`

### Phase 2: Snowflake Setup

#### 2.1 Generate RSA Key Pairs

```bash
# Generate keys for dev
openssl genrsa -out snowflake_dev.p8 2048
openssl rsa -in snowflake_dev.p8 -pubout -out snowflake_dev.pub
base64 -i snowflake_dev.p8 > snowflake_dev.p8.b64

# Generate keys for uat
openssl genrsa -out snowflake_uat.p8 2048
openssl rsa -in snowflake_uat.p8 -pubout -out snowflake_uat.pub
base64 -i snowflake_uat.p8 > snowflake_uat.p8.b64
```

#### 2.2 Create Snowflake Resources

Run these SQL commands in each Snowflake account:

**In sf-dev.west-europe.azure:**
```sql
USE ROLE ACCOUNTADMIN;

CREATE DATABASE DBT_MODELS_DEV;
CREATE WAREHOUSE COMPUTE_WH_DEV WITH WAREHOUSE_SIZE = 'XSMALL';
CREATE ROLE DBT_DEV_ROLE;

-- Paste public key from snowflake_dev.pub (remove header/footer)
CREATE USER DBT_DEV_USER RSA_PUBLIC_KEY='MIIB...';

GRANT ROLE DBT_DEV_ROLE TO USER DBT_DEV_USER;
GRANT ALL ON DATABASE DBT_MODELS_DEV TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH_DEV TO ROLE DBT_DEV_ROLE;

-- Create schemas
USE DATABASE DBT_MODELS_DEV;
CREATE SCHEMA staging;
CREATE SCHEMA intermediate;
```

**In sf-uat.west-europe.azure:**
```sql
USE ROLE ACCOUNTADMIN;

CREATE DATABASE DBT_MODELS_UAT;
CREATE WAREHOUSE COMPUTE_WH_UAT WITH WAREHOUSE_SIZE = 'SMALL';
CREATE ROLE DBT_UAT_ROLE;

-- Paste public key from snowflake_uat.pub
CREATE USER DBT_UAT_USER RSA_PUBLIC_KEY='MIIB...';

GRANT ROLE DBT_UAT_ROLE TO USER DBT_UAT_USER;
GRANT ALL ON DATABASE DBT_MODELS_UAT TO ROLE DBT_UAT_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH_UAT TO ROLE DBT_UAT_ROLE;

USE DATABASE DBT_MODELS_UAT;
CREATE SCHEMA staging;
CREATE SCHEMA intermediate;
```

#### 2.3 Upload Certificates to Azure Key Vault

```bash
az keyvault secret set \
  --vault-name secrets-aci-dev \
  --name snowflake-certificate-dev \
  --file snowflake_dev.p8.b64

az keyvault secret set \
  --vault-name secrets-aci-uat \
  --name snowflake-certificate-uat \
  --file snowflake_uat.p8.b64
```

### Phase 3: Deploy Terraform Infrastructure

#### 3.1 Deploy Baseline Infrastructure (DEV)

```bash
cd baseline-dev

# Initialize Terraform
terraform init

# Review plan
terraform plan

# Apply (creates ACR, Key Vault, Managed Identity)
terraform apply

cd ..
```

#### 3.2 Deploy Baseline Infrastructure (UAT)

```bash
cd baseline-uat
terraform init
terraform plan
terraform apply
cd ..
```

#### 3.3 Deploy Application Infrastructure (DEV)

```bash
cd infra-dev

# Initialize
terraform init

# Apply with image version
terraform apply -var='image_version=latest'

cd ..
```

#### 3.4 Deploy Application Infrastructure (UAT)

```bash
cd infra-uat
terraform init

# Use a specific release tag for UAT
terraform apply -var='image_version=rel-2026-01-09-1'

cd ..
```

### Phase 4: Test Deployment Flow

#### 4.1 Test DEV Auto-Deploy

```bash
# Make a small change
echo "# Test change" >> README.md

# Commit and push to main
git add README.md
git commit -m "Test dev auto-deploy"
git push origin main

# Watch GitHub Actions
# Go to: https://github.com/YOUR_ORG/YOUR_REPO/actions
# Verify "Deploy to DEV" workflow runs and succeeds
```

#### 4.2 Test UAT Manual Deploy

```bash
# Get the commit SHA from successful dev deployment
DEV_SHA="abc123"  # Replace with actual SHA

# Update UAT release config
vim release/uat.yaml
# Change: image_version: rel-2026-01-09-1

# Commit the change
git add release/uat.yaml
git commit -m "Promote $DEV_SHA to UAT"
git push origin main

# Create UAT release tag
git tag rel-2026-01-09-1-uat
git push origin rel-2026-01-09-1-uat

# Go to GitHub Actions and approve the UAT deployment
```

#### 4.3 Verify Deployments

**Check DEV:**
```bash
# View container logs
az container logs \
  --name dbt-job-dev \
  --resource-group az-euw-syn-dev-pract-dbt-rg01

# Connect to Snowflake dev and verify data
# USE DATABASE DBT_MODELS_DEV;
# SHOW TABLES IN SCHEMA staging;
```

**Check UAT:**
```bash
# View container logs
az container logs \
  --name dbt-job-uat \
  --resource-group az-euw-syn-uat-pract-dbt-rg01

# Connect to Snowflake UAT and verify data
# USE DATABASE DBT_MODELS_UAT;
# SHOW TABLES IN SCHEMA staging;
```

## Deployment Flow Diagram

```
Developer Workflow:
-------------------

1. Feature Development
   git checkout -b feature/new-metrics
   [make changes to DBT models]
   git push origin feature/new-metrics
   [create PR, review, merge to main]

   ↓ (automatic on merge)

2. DEV Deployment
   Workflow: deploy-dev.yml triggers
   - Reads release/dev.yaml
   - Builds Docker image (tag: commit-sha + latest)
   - Pushes to dbtjobsdev.azurecr.io
   - Deploys to ACI (dbt-job-dev)
   - Runs DBT with target=dev

   ✅ Verify in DEV Snowflake

   ↓ (manual)

3. UAT Promotion
   # Update release/uat.yaml with tested dev commit SHA
   vim release/uat.yaml
   # image_version: <commit-sha-from-dev>

   git add release/uat.yaml
   git commit -m "Promote <sha> to UAT"
   git push origin main

   git tag rel-2026-01-09-1-uat
   git push origin rel-2026-01-09-1-uat

   ↓

   Workflow: deploy-uat.yml triggers on tag
   - Validates tag matches release/uat.yaml
   - Verifies image exists in dev ACR
   - Imports image to UAT ACR
   - Deploys to ACI (dbt-job-uat)
   - Requires manual approval

   ✅ Verify in UAT Snowflake
```

## Rollback Procedures

### Rollback UAT Deployment

```bash
# 1. Identify last good release
git tag --sort=-creatordate | grep uat | head -5

# 2. Update release/uat.yaml
LAST_GOOD="rel-2026-01-08-3"
vim release/uat.yaml
# Change image_version to: rel-2026-01-08-3

# 3. Commit rollback
git add release/uat.yaml
git commit -m "[ROLLBACK] Revert UAT to $LAST_GOOD"
git push origin main

# 4. Create rollback tag
git tag ${LAST_GOOD}-uat-rollback
git push origin ${LAST_GOOD}-uat-rollback

# 5. Approve deployment (deploys previous version)
```

### Rollback with Snowflake Time Travel

```sql
-- If data was corrupted, use Time Travel
CREATE OR REPLACE TABLE staging.stg_customers AS
SELECT * FROM staging.stg_customers
AT(TIMESTAMP => '2026-01-09 10:00:00'::TIMESTAMP);
```

## Troubleshooting

### Issue: Workflow fails with "image not found"

**Cause:** Image version in release config doesn't exist in ACR

**Solution:**
```bash
# Check images in ACR
az acr repository show-tags \
  --name dbtjobsdev \
  --repository dbt/tpch_transform

# Update release config with valid tag
```

### Issue: ACI fails with "Key Vault access denied"

**Cause:** Managed identity doesn't have Key Vault permissions

**Solution:**
```bash
# Grant access manually
az role assignment create \
  --assignee <managed-identity-principal-id> \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/secrets-aci-dev
```

### Issue: DBT fails with "Snowflake authentication error"

**Cause:** Certificate not uploaded or incorrect format

**Solution:**
```bash
# Re-upload certificate
az keyvault secret set \
  --vault-name secrets-aci-dev \
  --name snowflake-certificate-dev \
  --file snowflake_dev.p8.b64

# Verify it's base64 encoded
cat snowflake_dev.p8.b64 | base64 -d | head -1
# Should show: -----BEGIN RSA PRIVATE KEY-----
```

## Cost Monitoring

Estimated monthly costs for dev + uat:

| Resource | Quantity | Monthly Cost |
|----------|----------|--------------|
| ACR Basic | 2 | $10 |
| Key Vault Standard | 2 | $2 |
| Storage Account | 2 | $2 |
| ACI (on-demand) | 2 | $5 |
| **Total** | | **~$19/month** |

Monitor costs:
```bash
az consumption usage list \
  --start-date 2026-01-01 \
  --end-date 2026-01-31 \
  --query "[?contains(instanceName, 'dbt')].{Name:instanceName, Cost:pretaxCost}" \
  --output table
```

## Additional Resources

- **Implementation Plan**: `/root/.claude/plans/distributed-foraging-moonbeam.md`
- **Scripts Documentation**: `scripts/README.md`
- **Release Configs**: `release/dev.yaml`, `release/uat.yaml`
- **Terraform Baseline**: `baseline-dev/`, `baseline-uat/`
- **Terraform Infrastructure**: `infra-dev/`, `infra-uat/`

## Maintenance

### Weekly Tasks
- Review UAT deployments
- Monitor Snowflake costs and query performance
- Check ACI execution logs for errors

### Monthly Tasks
- Review and clean up old Docker images in ACR
- Audit Key Vault access logs
- Review GitHub Actions usage

### Quarterly Tasks
- Rotate Snowflake RSA keys
- Review and update RBAC permissions
- Audit compliance with deployment procedures

---

**Last Updated:** 2026-01-09
**Environments:** dev, uat (prd disabled)
**Deployment Model:** Trunk-Based Development with Environment-Locked Release Configs
