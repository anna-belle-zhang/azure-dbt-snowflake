#!/bin/bash
set -euo pipefail

# =============================================================================
# Azure Baseline Resource Creator
# =============================================================================
# This script creates baseline Azure resources for each environment
# based on release/*.yaml configurations
#
# IMPORTANT: Run this AFTER validating with check-azure-resources.sh
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

# Subscription
SUBSCRIPTION_ID="ddfe89b6-c4e5-4d13-a3c0-441f618f19f7"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if yq is available
if ! command -v yq &> /dev/null; then
    print_error "yq not found. Please install yq first."
    exit 1
fi

# Verify Azure login
print_header "Verifying Azure Login"

if ! az account show &>/dev/null; then
    print_error "Not logged into Azure. Please run: az login"
    exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID"
CURRENT_SUB=$(az account show --query name -o tsv)
print_success "Logged into: $CURRENT_SUB"

# Function to create resources for an environment
create_environment_resources() {
    local env=$1
    local config_file="$PROJECT_ROOT/release/${env}.yaml"

    print_header "Creating Resources for $env Environment"

    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi

    # Extract values from config
    local location=$(yq '.azure.location' "$config_file")
    local rg_name=$(yq '.azure.resource_group' "$config_file")
    local acr_name=$(yq '.azure.acr_name' "$config_file")
    local acr_sku=$(yq '.azure.acr_sku' "$config_file")
    local kv_name=$(yq '.azure.keyvault_name' "$config_file")
    local kv_sku=$(yq '.azure.keyvault_sku' "$config_file")
    local storage_name=$(yq '.azure.storage_account_name' "$config_file")
    local storage_container=$(yq '.azure.storage_container_name' "$config_file")
    local soft_delete_days=$(yq '.azure.soft_delete_retention_days' "$config_file")
    local purge_protection=$(yq '.azure.purge_protection_enabled' "$config_file")

    print_info "Configuration:"
    echo "  Location: $location"
    echo "  Resource Group: $rg_name"
    echo "  ACR: $acr_name ($acr_sku)"
    echo "  Key Vault: $kv_name ($kv_sku)"
    echo "  Storage: $storage_name"
    echo ""

    # Step 1: Create Resource Group
    print_info "Creating Resource Group: $rg_name"
    if az group show --name "$rg_name" &>/dev/null; then
        print_warning "Resource Group already exists"
    else
        az group create \
            --name "$rg_name" \
            --location "$location" \
            --tags \
                environment="$env" \
                managed_by="script" \
                deployment_type="trunk-based"
        print_success "Resource Group created"
    fi

    # Step 2: Create Storage Account (for Terraform state)
    print_info "Creating Storage Account: $storage_name"
    if az storage account show --name "$storage_name" --resource-group "$rg_name" &>/dev/null; then
        print_warning "Storage Account already exists"
    else
        az storage account create \
            --name "$storage_name" \
            --resource-group "$rg_name" \
            --location "$location" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags \
                environment="$env" \
                purpose="terraform-state"
        print_success "Storage Account created"
    fi

    # Step 3: Create Storage Container
    print_info "Creating Storage Container: $storage_container"
    if az storage container exists \
        --name "$storage_container" \
        --account-name "$storage_name" \
        --query exists -o tsv 2>/dev/null | grep -q "true"; then
        print_warning "Storage Container already exists"
    else
        az storage container create \
            --name "$storage_container" \
            --account-name "$storage_name" \
            --auth-mode login
        print_success "Storage Container created"
    fi

    # Step 4: Create Container Registry
    print_info "Creating Container Registry: $acr_name"
    if az acr show --name "$acr_name" &>/dev/null; then
        print_warning "ACR already exists"
    else
        az acr create \
            --name "$acr_name" \
            --resource-group "$rg_name" \
            --location "$location" \
            --sku "$acr_sku" \
            --admin-enabled true \
            --tags \
                environment="$env"
        print_success "ACR created"
    fi

    # Get ACR credentials
    print_info "Retrieving ACR credentials..."
    ACR_USERNAME=$(az acr credential show --name "$acr_name" --query username -o tsv)
    ACR_PASSWORD=$(az acr credential show --name "$acr_name" --query "passwords[0].value" -o tsv)

    echo ""
    print_success "ACR Credentials (save as GitHub Secrets):"
    echo "  REGISTRY_USERNAME_${env^^}: $ACR_USERNAME"
    echo "  REGISTRY_PASSWORD_${env^^}: $ACR_PASSWORD"
    echo ""

    # Step 5: Create Key Vault
    print_info "Creating Key Vault: $kv_name"
    if az keyvault show --name "$kv_name" &>/dev/null; then
        print_warning "Key Vault already exists"
    else
        if [ "$purge_protection" == "true" ]; then
            az keyvault create \
                --name "$kv_name" \
                --resource-group "$rg_name" \
                --location "$location" \
                --sku "$kv_sku" \
                --enable-rbac-authorization false \
                --enabled-for-deployment true \
                --enabled-for-disk-encryption true \
                --retention-days "$soft_delete_days" \
                --enable-purge-protection true \
                --tags \
                    environment="$env"
        else
            az keyvault create \
                --name "$kv_name" \
                --resource-group "$rg_name" \
                --location "$location" \
                --sku "$kv_sku" \
                --enable-rbac-authorization false \
                --enabled-for-deployment true \
                --enabled-for-disk-encryption true \
                --retention-days "$soft_delete_days" \
                --tags \
                    environment="$env"
        fi
        print_success "Key Vault created"
    fi

    print_success "$env environment resources created successfully!"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================

print_header "Azure Baseline Resource Creator"

cat <<'EOF'

This script will create baseline resources for all environments:
- Resource Groups
- Storage Accounts (for Terraform state)
- Container Registries (ACR)
- Key Vaults

Prerequisites:
1. Logged into Azure (az login)
2. Validated resource names (./scripts/validate-names.sh)
3. Checked availability (./scripts/check-azure-resources.sh)

IMPORTANT: This creates resources that incur costs!
- ACR Basic: ~$5/month per registry
- Storage: ~$0.02/GB + operations
- Key Vault: ~$0.03 per 10k operations

EOF

read -p "Continue with resource creation? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    print_warning "Cancelled by user"
    exit 0
fi

# Create resources for each environment
for env in dev uat prd; do
    create_environment_resources "$env"
    sleep 2  # Brief pause between environments
done

# =============================================================================
# Summary and Next Steps
# =============================================================================

print_header "Summary and Next Steps"

cat <<'EOF'

✅ Baseline resources created for all environments!

Next Steps:
-----------

1. Generate Snowflake RSA Keys (per environment)
   -------------------------------------------
   for env in dev uat prd; do
     openssl genrsa -out snowflake_${env}.p8 2048
     openssl rsa -in snowflake_${env}.p8 -pubout -out snowflake_${env}.pub
     base64 -i snowflake_${env}.p8 > snowflake_${env}.p8.b64
   done

2. Create Snowflake Resources
   --------------------------
   For each environment, run in Snowflake:

   USE ROLE ACCOUNTADMIN;

   -- DEV
   CREATE DATABASE DBT_MODELS_DEV;
   CREATE WAREHOUSE COMPUTE_WH_DEV WITH WAREHOUSE_SIZE = 'XSMALL';
   CREATE ROLE DBT_DEV_ROLE;
   CREATE USER DBT_DEV_USER RSA_PUBLIC_KEY='<paste_public_key>';
   GRANT ROLE DBT_DEV_ROLE TO USER DBT_DEV_USER;
   GRANT ALL ON DATABASE DBT_MODELS_DEV TO ROLE DBT_DEV_ROLE;
   GRANT USAGE ON WAREHOUSE COMPUTE_WH_DEV TO ROLE DBT_DEV_ROLE;

   -- Repeat for UAT and PRD

3. Upload Certificates to Key Vault
   --------------------------------
   az keyvault secret set \
     --vault-name secrets-aci-dev \
     --name snowflake-certificate-dev \
     --file snowflake_dev.p8.b64

   az keyvault secret set \
     --vault-name secrets-aci-uat \
     --name snowflake-certificate-uat \
     --file snowflake_uat.p8.b64

   az keyvault secret set \
     --vault-name secrets-aci-prd \
     --name snowflake-certificate-prd \
     --file snowflake_prd.p8.b64

4. Set GitHub Secrets
   ------------------
   Repository Settings → Secrets and variables → Actions → New repository secret

   AZURE_CREDENTIALS (Service Principal JSON)
   AZURE_CLIENT_ID
   AZURE_CLIENT_SECRET
   AZURE_SUBSCRIPTION_ID
   AZURE_TENANT_ID
   REGISTRY_USERNAME_DEV (from output above)
   REGISTRY_PASSWORD_DEV (from output above)
   REGISTRY_USERNAME_UAT
   REGISTRY_PASSWORD_UAT
   REGISTRY_USERNAME_PRD
   REGISTRY_PASSWORD_PRD

5. Create GitHub Environments
   --------------------------
   Settings → Environments → New environment

   - dev: No protection rules
   - uat: Required reviewers (1), Deployment branches: Tags (rel-*-uat)
   - prd: Required reviewers (2), Deployment branches: Tags (rel-*-prd)

6. Deploy Terraform Infrastructure
   -------------------------------
   cd baseline-dev && terraform init && terraform apply
   cd baseline-uat && terraform init && terraform apply
   cd baseline-prd && terraform init && terraform apply

   cd infra-dev && terraform init && terraform apply
   cd infra-uat && terraform init && terraform apply
   cd infra-prd && terraform init && terraform apply

EOF

print_success "All done! Refer to the plan file for detailed next steps."
print_info "Plan file: /root/.claude/plans/distributed-foraging-moonbeam.md"
