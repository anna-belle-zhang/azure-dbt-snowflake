#!/bin/bash
set -euo pipefail

# =============================================================================
# Azure Resource Availability Checker
# =============================================================================
# This script checks:
# 1. Resource name availability (ACR, Key Vault, Storage Account)
# 2. Current quotas and limits
# 3. Existing resources in subscription
# 4. Cost estimates
#
# Tenant: Blackwoods Australia
# Subscription: Visual Studio Professional Subscription
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tenant and Subscription
TENANT_NAME="Blackwoods Australia"
SUBSCRIPTION_ID="ddfe89b6-c4e5-4d13-a3c0-441f618f19f7"
LOCATION="westeurope"

# Resource names to check (from release configs)
ACR_NAMES=("dbtjobsdev" "dbtjobsuat" "dbtjobsprd")
KV_NAMES=("secrets-aci-dev" "secrets-aci-uat" "secrets-aci-prd")
STORAGE_NAMES=("azeuwsyndevstategsa01" "azeuwsynuatstategsa01" "azeuwsynprdstategsa01")

# Function to print section headers
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to print info
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# =============================================================================
# Step 1: Azure Login
# =============================================================================
print_header "Step 1: Azure Login"

echo "Logging into Azure..."
echo "Tenant: $TENANT_NAME"
echo "Subscription ID: $SUBSCRIPTION_ID"
echo ""

# Login to Azure
az login --use-device-code

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Verify logged in
CURRENT_SUB=$(az account show --query name -o tsv)
CURRENT_SUB_ID=$(az account show --query id -o tsv)

print_success "Logged in successfully"
print_info "Current Subscription: $CURRENT_SUB"
print_info "Subscription ID: $CURRENT_SUB_ID"

# =============================================================================
# Step 2: Check Container Registry Name Availability
# =============================================================================
print_header "Step 2: Checking ACR Name Availability"

echo "Checking Container Registry names..."
echo ""

for acr_name in "${ACR_NAMES[@]}"; do
    echo -n "Checking '$acr_name'... "

    # Check name availability
    result=$(az acr check-name --name "$acr_name" --output json 2>/dev/null || echo '{"nameAvailable": false, "message": "Error checking name"}')

    available=$(echo "$result" | jq -r '.nameAvailable')
    message=$(echo "$result" | jq -r '.message // "N/A"')

    if [ "$available" == "true" ]; then
        print_success "Available"
    else
        print_error "Not Available - $message"
    fi
done

# =============================================================================
# Step 3: Check Key Vault Name Availability
# =============================================================================
print_header "Step 3: Checking Key Vault Name Availability"

echo "Checking Key Vault names..."
echo ""

for kv_name in "${KV_NAMES[@]}"; do
    echo -n "Checking '$kv_name'... "

    # Key Vault names must be globally unique
    # We'll try to check by attempting to show it
    result=$(az keyvault list --query "[?name=='$kv_name'].name" -o tsv 2>/dev/null)

    if [ -z "$result" ]; then
        # Not found in current subscription, check global availability
        # Key Vault doesn't have a direct "check-name" API, so we test DNS
        kv_fqdn="${kv_name}.vault.azure.net"
        if nslookup "$kv_fqdn" &>/dev/null; then
            print_error "Not Available (exists globally)"
        else
            print_success "Available"
        fi
    else
        print_warning "Already exists in current subscription"
    fi
done

# =============================================================================
# Step 4: Check Storage Account Name Availability
# =============================================================================
print_header "Step 4: Checking Storage Account Name Availability"

echo "Checking Storage Account names..."
echo ""

for storage_name in "${STORAGE_NAMES[@]}"; do
    echo -n "Checking '$storage_name'... "

    # Check storage account name availability
    result=$(az storage account check-name --name "$storage_name" --output json 2>/dev/null || echo '{"nameAvailable": false}')

    available=$(echo "$result" | jq -r '.nameAvailable')
    reason=$(echo "$result" | jq -r '.reason // "N/A"')
    message=$(echo "$result" | jq -r '.message // "N/A"')

    if [ "$available" == "true" ]; then
        print_success "Available"
    else
        print_error "Not Available - Reason: $reason, Message: $message"
    fi
done

# =============================================================================
# Step 5: List Existing Resources
# =============================================================================
print_header "Step 5: Existing Resources in Subscription"

echo "Resource Groups:"
az group list --query "[].{Name:name, Location:location}" -o table

echo ""
echo "Container Registries:"
az acr list --query "[].{Name:name, Location:location, SKU:sku.name}" -o table 2>/dev/null || echo "None found"

echo ""
echo "Key Vaults:"
az keyvault list --query "[].{Name:name, Location:location}" -o table 2>/dev/null || echo "None found"

echo ""
echo "Storage Accounts:"
az storage account list --query "[].{Name:name, Location:location, SKU:sku.name}" -o table 2>/dev/null || echo "None found"

echo ""
echo "Container Instances:"
az container list --query "[].{Name:name, Location:location, State:instanceView.state}" -o table 2>/dev/null || echo "None found"

# =============================================================================
# Step 6: Check Quotas and Limits
# =============================================================================
print_header "Step 6: Subscription Quotas and Limits"

echo "Checking compute quotas for location: $LOCATION"
echo ""

# Get compute quotas
echo "Virtual Machine Quotas:"
az vm list-usage --location "$LOCATION" --query "[?contains(name.value, 'StandardD')].{Name:name.localizedValue, Current:currentValue, Limit:limit}" -o table 2>/dev/null | head -10

echo ""
echo "Storage Account Limits:"
az storage account list --query "length(@)" -o tsv 2>/dev/null | xargs -I {} echo "Current Storage Accounts: {} / 250 (per subscription)"

echo ""
echo "Container Registry Limits:"
az acr list --query "length(@)" -o tsv 2>/dev/null | xargs -I {} echo "Current ACRs: {} / Unlimited (Basic/Standard/Premium SKUs)"

# =============================================================================
# Step 7: Resource Pricing Estimates
# =============================================================================
print_header "Step 7: Estimated Monthly Costs (West Europe)"

cat <<EOF

Resource                        | SKU/Size           | Estimated Monthly Cost
--------------------------------|--------------------|-----------------------
Container Registry (Basic)      | Basic              | ~\$5 USD
Container Registry (Standard)   | Standard           | ~\$20 USD
Container Registry (Premium)    | Premium            | ~\$500 USD
Key Vault (Standard)            | Standard           | ~\$0.03 per 10k ops
Key Vault (Premium/HSM)         | Premium            | ~\$1/hour (~\$730/mo)
Storage Account (LRS)           | Standard_LRS       | ~\$0.02/GB + ops
Container Instance (0.5 CPU)    | 0.5 CPU, 1GB RAM   | ~\$0.0000125/sec (~\$33/mo continuous)
Container Instance (2 CPU)      | 2 CPU, 4GB RAM     | ~\$0.0000500/sec (~\$130/mo continuous)

Notes:
- ACI charges per second of execution (use restart_policy="Never" for job-based)
- Storage costs include operations (list, read, write)
- ACR includes 10GB storage (Basic), 100GB (Standard), 500GB (Premium)
- Key Vault operations: GET secret ~\$0.03/10k operations

Estimated Total for Dev/UAT/PRD Setup:
- 3x ACR Basic: ~\$15/mo
- 3x Key Vault Standard: ~\$5/mo (low usage)
- 3x Storage Account: ~\$2/mo (Terraform state)
- 3x ACI (run-once jobs): ~\$5/mo (assuming 1 hour total runtime)
**Total: ~\$27 USD/month**

EOF

# =============================================================================
# Step 8: Naming Convention Validation
# =============================================================================
print_header "Step 8: Naming Convention Validation"

echo "Validating resource names against Azure naming rules..."
echo ""

# ACR naming rules
echo "Container Registry Names (3-50 chars, alphanumeric only):"
for acr_name in "${ACR_NAMES[@]}"; do
    length=${#acr_name}
    if [[ $length -ge 3 && $length -le 50 && "$acr_name" =~ ^[a-zA-Z0-9]+$ ]]; then
        print_success "$acr_name (length: $length) - Valid"
    else
        print_error "$acr_name (length: $length) - Invalid"
    fi
done

echo ""
echo "Key Vault Names (3-24 chars, alphanumeric and hyphens, start with letter):"
for kv_name in "${KV_NAMES[@]}"; do
    length=${#kv_name}
    if [[ $length -ge 3 && $length -le 24 && "$kv_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        print_success "$kv_name (length: $length) - Valid"
    else
        print_error "$kv_name (length: $length) - Invalid"
    fi
done

echo ""
echo "Storage Account Names (3-24 chars, lowercase alphanumeric only):"
for storage_name in "${STORAGE_NAMES[@]}"; do
    length=${#storage_name}
    if [[ $length -ge 3 && $length -le 24 && "$storage_name" =~ ^[a-z0-9]+$ ]]; then
        print_success "$storage_name (length: $length) - Valid"
    else
        print_error "$storage_name (length: $length) - Invalid"
    fi
done

# =============================================================================
# Step 9: GitHub Actions Readiness Check
# =============================================================================
print_header "Step 9: GitHub Actions Integration Readiness"

echo "Checking if Service Principal exists for GitHub Actions..."
echo ""

# Note: This requires additional permissions to list service principals
SP_NAME="github-actions-dbt"
echo "Expected Service Principal Name: $SP_NAME"
print_warning "You'll need to create a service principal for GitHub Actions:"

cat <<'EOF'

Create Service Principal:
-------------------------
az ad sp create-for-rbac \
  --name "github-actions-dbt" \
  --role contributor \
  --scopes /subscriptions/ddfe89b6-c4e5-4d13-a3c0-441f618f19f7 \
  --sdk-auth

Save the JSON output as GitHub Secret: AZURE_CREDENTIALS

Also set these GitHub Secrets:
- AZURE_CLIENT_ID
- AZURE_CLIENT_SECRET
- AZURE_SUBSCRIPTION_ID (ddfe89b6-c4e5-4d13-a3c0-441f618f19f7)
- AZURE_TENANT_ID

For each ACR, get credentials:
az acr credential show --name <acr-name>

Set as GitHub Secrets:
- REGISTRY_USERNAME_DEV
- REGISTRY_PASSWORD_DEV
- REGISTRY_USERNAME_UAT
- REGISTRY_PASSWORD_UAT
- REGISTRY_USERNAME_PRD
- REGISTRY_PASSWORD_PRD

EOF

# =============================================================================
# Step 10: Summary Report
# =============================================================================
print_header "Step 10: Summary Report"

cat <<EOF

Subscription Summary:
--------------------
Tenant: $TENANT_NAME
Subscription: $CURRENT_SUB
Subscription ID: $CURRENT_SUB_ID
Location: $LOCATION

Next Steps:
-----------
1. ✅ Review name availability above
2. 📝 Update release/*.yaml if names are unavailable
3. 🏗️  Create baseline infrastructure per environment:
   - Resource Groups
   - Storage Accounts (for Terraform state)
   - Deploy baseline Terraform (ACR, Key Vault)
4. 🔐 Generate Snowflake RSA keys (per environment)
5. ⚙️  Configure Snowflake (databases, warehouses, roles)
6. 🔑 Upload certificates to Key Vault
7. 🐙 Set up GitHub Secrets and Environments
8. 🚀 Deploy infrastructure Terraform (ACI)

Documentation:
-------------
- Plan file: /root/.claude/plans/distributed-foraging-moonbeam.md
- Release configs: /mnt/e/A/azure-dbt-snowflake/release/
- Workflows: /mnt/e/A/azure-dbt-snowflake/.github/workflows/

EOF

print_success "Azure resource check complete!"
