# Quick Start Guide - Trunk-Based DBT Deployment

## Prerequisites ✅

- [x] Azure resources created (dev, uat)
- [x] Logged into `az` CLI
- [x] Logged into `gh` CLI
- [x] Terraform configurations generated (baseline-dev/, infra-dev/, etc.)

## 5-Minute Setup

### 1. Setup Managed Identities (2 min)

```bash
./scripts/setup-managed-identities.sh
```

Copy the output JSON to `.secrets/github-sp-credentials.json` (auto-saved)

### 2. Configure GitHub Secrets (2 min)

Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/secrets/actions`

**From setup-managed-identities.sh output:**
- `AZURE_CREDENTIALS` = <entire JSON>
- `AZURE_CLIENT_ID` = <client_id>
- `AZURE_CLIENT_SECRET` = <client_secret>
- `AZURE_SUBSCRIPTION_ID` = ddfe89b6-c4e5-4d13-a3c0-441f618f19f7
- `AZURE_TENANT_ID` = <tenant_id>

**Get ACR credentials:**
```bash
az acr credential show --name dbtjobsdev --query "{username:username, password:passwords[0].value}"
az acr credential show --name dbtjobsuat --query "{username:username, password:passwords[0].value}"
```

Add as secrets:
- `REGISTRY_USERNAME_DEV`
- `REGISTRY_PASSWORD_DEV`
- `REGISTRY_USERNAME_UAT`
- `REGISTRY_PASSWORD_UAT`

### 3. Create GitHub Environments (1 min)

Go to: `https://github.com/YOUR_ORG/YOUR_REPO/settings/environments`

**dev:** No protection rules

**uat:**
- ✅ Required reviewers: 1
- ✅ Deployment branches: Tags matching `rel-*-uat`

## Snowflake Setup (15 min)

### Generate Keys

```bash
# DEV
openssl genrsa -out snowflake_dev.p8 2048
openssl rsa -in snowflake_dev.p8 -pubout -out snowflake_dev.pub
base64 -i snowflake_dev.p8 > snowflake_dev.p8.b64

# UAT
openssl genrsa -out snowflake_uat.p8 2048
openssl rsa -in snowflake_uat.p8 -pubout -out snowflake_uat.pub
base64 -i snowflake_uat.p8 > snowflake_uat.p8.b64
```

### Create Snowflake Resources

**In sf-dev.west-europe.azure:**
```sql
CREATE DATABASE DBT_MODELS_DEV;
CREATE WAREHOUSE COMPUTE_WH_DEV WITH WAREHOUSE_SIZE = 'XSMALL';
CREATE ROLE DBT_DEV_ROLE;
CREATE USER DBT_DEV_USER RSA_PUBLIC_KEY='<paste_from_snowflake_dev.pub>';
GRANT ROLE DBT_DEV_ROLE TO USER DBT_DEV_USER;
GRANT ALL ON DATABASE DBT_MODELS_DEV TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH_DEV TO ROLE DBT_DEV_ROLE;
```

**In sf-uat.west-europe.azure:** (same commands, replace DEV with UAT)

### Upload to Key Vault

```bash
az keyvault secret set --vault-name secrets-aci-dev --name snowflake-certificate-dev --file snowflake_dev.p8.b64
az keyvault secret set --vault-name secrets-aci-uat --name snowflake-certificate-uat --file snowflake_uat.p8.b64
```

## Deploy Infrastructure (10 min)

### Baseline (DEV)

```bash
cd baseline-dev
terraform init
terraform apply  # Review and type 'yes'
cd ..
```

### Baseline (UAT)

```bash
cd baseline-uat
terraform init
terraform apply
cd ..
```

### Application (DEV)

```bash
cd infra-dev
terraform init
terraform apply -var='image_version=latest'
cd ..
```

### Application (UAT)

```bash
cd infra-uat
terraform init
terraform apply -var='image_version=rel-2026-01-09-1'
cd ..
```

## Test Deployment (5 min)

### Test DEV Auto-Deploy

```bash
echo "# Test" >> README.md
git add README.md
git commit -m "Test dev deployment"
git push origin main
```

Watch: https://github.com/YOUR_ORG/YOUR_REPO/actions

### Verify DEV Container

```bash
az container logs --name dbt-job-dev --resource-group az-euw-syn-dev-pract-dbt-rg01
```

### Test UAT Deployment

```bash
# Update UAT config with dev commit SHA
vim release/uat.yaml
# Change: image_version: <commit-sha>

git add release/uat.yaml
git commit -m "Promote to UAT"
git push origin main

# Tag for UAT
git tag rel-2026-01-09-1-uat
git push origin rel-2026-01-09-1-uat

# Approve in GitHub UI
```

## Common Commands

### View Container Logs

```bash
# DEV
az container logs --name dbt-job-dev --resource-group az-euw-syn-dev-pract-dbt-rg01

# UAT
az container logs --name dbt-job-uat --resource-group az-euw-syn-uat-pract-dbt-rg01
```

### Check Snowflake Tables

```sql
-- DEV
USE DATABASE DBT_MODELS_DEV;
SHOW TABLES IN SCHEMA staging;
SELECT COUNT(*) FROM staging.stg_customers;

-- UAT
USE DATABASE DBT_MODELS_UAT;
SHOW TABLES IN SCHEMA staging;
SELECT COUNT(*) FROM staging.stg_customers;
```

### List Docker Images

```bash
az acr repository show-tags --name dbtjobsdev --repository dbt/tpch_transform
az acr repository show-tags --name dbtjobsuat --repository dbt/tpch_transform
```

### Rollback UAT

```bash
# Find last good release
git tag --sort=-creatordate | grep uat | head -5

# Update config
vim release/uat.yaml
# Change: image_version: rel-2026-01-08-3

# Commit and tag
git add release/uat.yaml
git commit -m "[ROLLBACK] UAT to rel-2026-01-08-3"
git push origin main
git tag rel-2026-01-08-3-uat-rollback
git push origin rel-2026-01-08-3-uat-rollback
```

## Troubleshooting

### "Image not found in ACR"

```bash
# Check what images exist
az acr repository show-tags --name dbtjobsdev --repository dbt/tpch_transform

# Update release config with valid tag
vim release/uat.yaml
```

### "Key Vault access denied"

```bash
# Check managed identity
az identity show --name dbt-aci-dev-identity --resource-group az-euw-syn-dev-pract-dbt-rg01

# Check role assignment
az role assignment list --scope /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/secrets-aci-dev
```

### "Snowflake authentication failed"

```bash
# Verify certificate in Key Vault
az keyvault secret show --vault-name secrets-aci-dev --name snowflake-certificate-dev --query value -o tsv | base64 -d | head -1
# Should show: -----BEGIN RSA PRIVATE KEY-----

# Re-upload if needed
az keyvault secret set --vault-name secrets-aci-dev --name snowflake-certificate-dev --file snowflake_dev.p8.b64
```

## File Structure

```
azure-dbt-snowflake/
├── release/
│   ├── dev.yaml                  # DEV config
│   ├── uat.yaml                  # UAT config
│   └── archive/prd.yaml.disabled # PRD (archived)
├── .github/workflows/
│   ├── deploy-dev.yml            # Auto-deploy on push to main
│   ├── deploy-uat.yml            # Deploy on rel-*-uat tag
│   └── archive/deploy-prd.yml.disabled
├── baseline-dev/                 # DEV baseline Terraform
├── baseline-uat/                 # UAT baseline Terraform
├── infra-dev/                    # DEV infra Terraform
├── infra-uat/                    # UAT infra Terraform
├── tpch_transform/
│   ├── profiles.yml              # DBT profiles (dev, uat)
│   ├── entrypoint.sh             # Parameterized entrypoint
│   └── models/                   # DBT models
└── scripts/
    ├── setup-managed-identities.sh
    ├── generate-terraform-envs.sh
    └── push-to-github.sh
```

## Cost Monitoring

```bash
# Monthly estimate: ~$19
# - ACR Basic (x2): $10
# - Key Vault (x2): $2
# - Storage (x2): $2
# - ACI (x2): $5

# Check actual costs
az consumption usage list --start-date 2026-01-01 --end-date 2026-01-31
```

## Next Steps

1. ✅ Complete Snowflake setup
2. ✅ Deploy baseline Terraform
3. ✅ Deploy infra Terraform
4. ✅ Test dev auto-deploy
5. ✅ Test UAT manual deploy
6. 📖 Read DEPLOYMENT_GUIDE.md for detailed procedures
7. 🔒 Enable branch protection on main
8. 📊 Set up monitoring alerts

---

**Support:** See DEPLOYMENT_GUIDE.md for detailed instructions
**Environments:** dev (auto), uat (manual)
**Cost:** ~$19/month
