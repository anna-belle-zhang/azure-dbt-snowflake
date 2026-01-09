# Azure DBT Snowflake - Helper Scripts

This directory contains helper scripts for managing Azure resources and deploying the trunk-based development infrastructure.

## Scripts Overview

### 1. `validate-names.sh` (No Azure Login Required)

**Purpose:** Validates resource naming conventions from `release/*.yaml` configs without requiring Azure login.

**Usage:**
```bash
./scripts/validate-names.sh
```

**What it does:**
- ✅ Validates ACR names (3-50 chars, alphanumeric)
- ✅ Validates Key Vault names (3-24 chars, alphanumeric+hyphens, starts with letter)
- ✅ Validates Storage Account names (3-24 chars, lowercase alphanumeric)
- ✅ Displays Snowflake configuration from release configs
- ✅ Provides setup checklist

**When to use:** Run this FIRST to validate your naming conventions before attempting any Azure operations.

---

### 2. `check-azure-resources.sh` (Requires Azure Login)

**Purpose:** Comprehensive Azure resource availability checker with quota and cost estimates.

**Usage:**
```bash
./scripts/check-azure-resources.sh
```

**What it does:**
- 🔐 Logs into Azure (device code flow)
- 🔍 Checks resource name availability (ACR, Key Vault, Storage)
- 📊 Lists existing resources in subscription
- 📈 Displays quotas and limits
- 💰 Provides cost estimates (~$27/month for all environments)
- ✅ Validates naming conventions
- 📝 Provides GitHub Actions setup instructions

**When to use:** Run this SECOND after validating names, to check actual availability in Azure.

**Prerequisites:**
- Azure CLI installed (`az` command available)
- Access to subscription: Visual Studio Professional Subscription (ddfe89b6-c4e5-4d13-a3c0-441f618f19f7)
- Tenant: Blackwoods Australia

---

### 3. `create-azure-baseline.sh` (Requires Azure Login)

**Purpose:** Creates baseline Azure resources for all environments (dev, uat, prd).

**Usage:**
```bash
./scripts/create-azure-baseline.sh
```

**What it creates (per environment):**
- 📦 Resource Group
- 💾 Storage Account (for Terraform state)
- 🗂️ Storage Container (for .tfstate files)
- 🐳 Container Registry (ACR with admin enabled)
- 🔐 Key Vault (with appropriate SKU and purge protection settings)

**When to use:** Run this THIRD after validating availability, to actually create the Azure resources.

**Important:**
- Creates resources that **incur costs** (~$27/month total)
- Retrieves and displays ACR credentials for GitHub Secrets
- Prompts for confirmation before creating resources
- Can be run multiple times (checks if resources exist)

**Output:**
- ACR credentials for each environment (save as GitHub Secrets)
- Next steps checklist for Snowflake setup and GitHub configuration

---

## Recommended Workflow

### Phase 1: Validation (No Azure Required)
```bash
# Step 1: Validate naming conventions
./scripts/validate-names.sh
```

### Phase 2: Azure Availability Check (Requires Azure Login)
```bash
# Step 2: Check resource availability and quotas
./scripts/check-azure-resources.sh
```

### Phase 3: Resource Creation (Requires Azure Login + Confirmation)
```bash
# Step 3: Create baseline resources
./scripts/create-azure-baseline.sh
```

### Phase 4: Snowflake Setup (Manual)
```bash
# Step 4a: Generate RSA key pairs
for env in dev uat prd; do
  openssl genrsa -out snowflake_${env}.p8 2048
  openssl rsa -in snowflake_${env}.p8 -pubout -out snowflake_${env}.pub
  base64 -i snowflake_${env}.p8 > snowflake_${env}.p8.b64
done

# Step 4b: Upload certificates to Key Vault
az keyvault secret set \
  --vault-name secrets-aci-dev \
  --name snowflake-certificate-dev \
  --file snowflake_dev.p8.b64
```

### Phase 5: GitHub Configuration (Manual)
- Set repository secrets (ACR credentials from create-azure-baseline.sh output)
- Create GitHub Environments (dev, uat, prd)
- Configure protection rules (reviewers, branch restrictions)

### Phase 6: Terraform Deployment
```bash
# Deploy baseline Terraform (per environment)
cd baseline-dev && terraform init && terraform apply

# Deploy infrastructure Terraform (per environment)
cd infra-dev && terraform init && terraform apply
```

---

## Prerequisites

### Required Tools
- **Azure CLI**: `az` command (install: https://docs.microsoft.com/cli/azure/install-azure-cli)
- **jq**: JSON processor (install: `sudo apt-get install jq`)
- **yq**: YAML processor (auto-installed by scripts if missing)
- **OpenSSL**: For generating Snowflake RSA keys (usually pre-installed)

### Azure Access
- **Subscription ID**: ddfe89b6-c4e5-4d13-a3c0-441f618f19f7
- **Tenant**: Blackwoods Australia
- **Permissions**: Contributor role on subscription

### Snowflake Access
- **Admin access** to Snowflake accounts (dev, uat, prd)
- Ability to create databases, warehouses, roles, and users

---

## Cost Estimates (West Europe)

| Resource | Environment | SKU | Monthly Cost |
|----------|-------------|-----|--------------|
| Container Registry | dev | Basic | ~$5 |
| Container Registry | uat | Basic | ~$5 |
| Container Registry | prd | Standard | ~$20 |
| Key Vault | dev | Standard | ~$1 |
| Key Vault | uat | Standard | ~$1 |
| Key Vault | prd | Premium | ~$730 |
| Storage Account | all | LRS | ~$2 |
| Container Instance | all | on-demand | ~$5 |

**Total (with Basic/Standard SKUs): ~$27/month**
**Total (with PRD Premium Key Vault): ~$757/month**

**Recommendation:** Start with Standard Key Vault for PRD unless HSM-backed keys are required.

---

## Troubleshooting

### Issue: "az command not found"
**Solution:** Install Azure CLI
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Issue: "jq command not found"
**Solution:** Install jq
```bash
sudo apt-get update && sudo apt-get install -y jq
```

### Issue: "Resource name already taken"
**Solution:** Update the resource name in `release/<env>.yaml` and re-run validation

### Issue: "Subscription not found"
**Solution:** Verify you're logged into the correct tenant
```bash
az account show
az account set --subscription ddfe89b6-c4e5-4d13-a3c0-441f618f19f7
```

### Issue: "Access denied to Key Vault"
**Solution:** Grant yourself access
```bash
az keyvault set-policy \
  --name secrets-aci-dev \
  --upn your-email@company.com \
  --secret-permissions get list set delete
```

---

## Related Documentation

- **Implementation Plan**: `/root/.claude/plans/distributed-foraging-moonbeam.md`
- **Release Configs**: `../release/*.yaml`
- **Workflows**: `../.github/workflows/deploy-*.yml`
- **DBT Profiles**: `../tpch_transform/profiles.yml`
- **Entrypoint Script**: `../tpch_transform/entrypoint.sh`

---

## Support

For questions or issues:
1. Review the implementation plan: `/root/.claude/plans/distributed-foraging-moonbeam.md`
2. Check script output for detailed error messages
3. Verify Azure permissions and subscription access
4. Ensure all prerequisites are installed

---

**Last Updated:** 2026-01-09
**Subscription:** Visual Studio Professional Subscription (Blackwoods Australia)
**Deployment Model:** Trunk-Based Development with Environment-Locked Release Configs
