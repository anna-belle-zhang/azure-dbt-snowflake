#!/bin/bash
set -euo pipefail

# =============================================================================
# Setup Managed Identities for GitHub Actions and Container Instances
# =============================================================================
# This script creates:
# 1. Service Principal for GitHub Actions (dev, uat)
# 2. User-assigned managed identities for ACI containers (dev, uat)
# 3. RBAC role assignments for Key Vault access
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

# Configuration
SUBSCRIPTION_ID="ddfe89b6-c4e5-4d13-a3c0-441f618f19f7"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check yq
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

# =============================================================================
# Step 1: Create Service Principal for GitHub Actions
# =============================================================================
print_header "Step 1: Creating Service Principal for GitHub Actions"

SP_NAME="github-actions-dbt-pipeline"

print_info "Checking if Service Principal exists..."

# Check if SP already exists
SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$SP_APP_ID" ]; then
    print_warning "Service Principal '$SP_NAME' already exists (App ID: $SP_APP_ID)"
    print_info "Retrieving existing credentials..."

    # Reset credentials to get new secret
    SP_CREDENTIALS=$(az ad sp credential reset --id "$SP_APP_ID" --output json 2>/dev/null)
else
    print_info "Creating new Service Principal..."

    # Create service principal with contributor role on subscription
    SP_CREDENTIALS=$(az ad sp create-for-rbac \
        --name "$SP_NAME" \
        --role contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --sdk-auth)

    SP_APP_ID=$(echo "$SP_CREDENTIALS" | jq -r '.clientId')
    print_success "Service Principal created"
fi

print_success "Service Principal: $SP_NAME"
print_info "App ID: $SP_APP_ID"

# Extract credentials
SP_CLIENT_ID=$(echo "$SP_CREDENTIALS" | jq -r '.clientId')
SP_CLIENT_SECRET=$(echo "$SP_CREDENTIALS" | jq -r '.clientSecret')
SP_TENANT_ID=$(echo "$SP_CREDENTIALS" | jq -r '.tenantId')

# Get object ID for role assignments
SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id -o tsv)

echo ""
print_success "GitHub Secrets to set:"
echo "========================================"
echo "AZURE_CREDENTIALS:"
echo "$SP_CREDENTIALS" | jq '.'
echo ""
echo "AZURE_CLIENT_ID: $SP_CLIENT_ID"
echo "AZURE_CLIENT_SECRET: $SP_CLIENT_SECRET"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "AZURE_TENANT_ID: $SP_TENANT_ID"
echo "========================================"

# Save to file
mkdir -p "$PROJECT_ROOT/.secrets"
echo "$SP_CREDENTIALS" > "$PROJECT_ROOT/.secrets/github-sp-credentials.json"
print_info "Credentials saved to: .secrets/github-sp-credentials.json"
print_warning "⚠️  Keep this file secure! Add .secrets/ to .gitignore"

# =============================================================================
# Step 2: Grant Service Principal Access to Key Vaults
# =============================================================================
print_header "Step 2: Granting Service Principal Access to Key Vaults"

for env in dev uat; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        print_warning "Config file not found: $config_file"
        continue
    fi

    kv_name=$(yq '.azure.keyvault_name' "$config_file")
    rg_name=$(yq '.azure.resource_group' "$config_file")

    print_info "Granting access to $kv_name..."

    # Check if Key Vault exists
    if ! az keyvault show --name "$kv_name" --resource-group "$rg_name" &>/dev/null; then
        print_warning "Key Vault $kv_name does not exist, skipping..."
        continue
    fi

    # Grant Key Vault Secrets User role
    KV_ID=$(az keyvault show --name "$kv_name" --query id -o tsv)

    az role assignment create \
        --assignee "$SP_OBJECT_ID" \
        --role "Key Vault Secrets User" \
        --scope "$KV_ID" \
        2>/dev/null || print_warning "Role assignment may already exist"

    print_success "Access granted to $kv_name"
done

# =============================================================================
# Step 3: Create User-Assigned Managed Identities for ACI
# =============================================================================
print_header "Step 3: Creating Managed Identities for Container Instances"

for env in dev uat; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        print_warning "Config file not found: $config_file"
        continue
    fi

    rg_name=$(yq '.azure.resource_group' "$config_file")
    location=$(yq '.azure.location' "$config_file")
    kv_name=$(yq '.azure.keyvault_name' "$config_file")

    # Managed identity name
    MI_NAME="dbt-aci-${env}-identity"

    print_info "Creating managed identity: $MI_NAME in $rg_name..."

    # Check if managed identity exists
    MI_ID=$(az identity show --name "$MI_NAME" --resource-group "$rg_name" --query id -o tsv 2>/dev/null || echo "")

    if [ -n "$MI_ID" ]; then
        print_warning "Managed identity already exists"
    else
        MI_ID=$(az identity create \
            --name "$MI_NAME" \
            --resource-group "$rg_name" \
            --location "$location" \
            --query id -o tsv)

        print_success "Managed identity created"
        sleep 10  # Wait for identity propagation
    fi

    # Get principal ID
    MI_PRINCIPAL_ID=$(az identity show --ids "$MI_ID" --query principalId -o tsv)
    MI_CLIENT_ID=$(az identity show --ids "$MI_ID" --query clientId -o tsv)

    print_info "Managed Identity Details:"
    echo "  Name: $MI_NAME"
    echo "  Resource ID: $MI_ID"
    echo "  Principal ID: $MI_PRINCIPAL_ID"
    echo "  Client ID: $MI_CLIENT_ID"

    # Grant Key Vault access
    print_info "Granting Key Vault access to managed identity..."

    if az keyvault show --name "$kv_name" --resource-group "$rg_name" &>/dev/null; then
        KV_ID=$(az keyvault show --name "$kv_name" --query id -o tsv)

        az role assignment create \
            --assignee "$MI_PRINCIPAL_ID" \
            --role "Key Vault Secrets User" \
            --scope "$KV_ID" \
            2>/dev/null || print_warning "Role assignment may already exist"

        print_success "Key Vault access granted"
    else
        print_warning "Key Vault $kv_name does not exist"
    fi

    echo ""
done

# =============================================================================
# Step 4: Grant ACR Pull Access to Service Principal
# =============================================================================
print_header "Step 4: Granting ACR Pull Access to Service Principal"

for env in dev uat; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        continue
    fi

    acr_name=$(yq '.azure.acr_name' "$config_file")

    print_info "Granting ACR pull access to $acr_name..."

    if az acr show --name "$acr_name" &>/dev/null; then
        ACR_ID=$(az acr show --name "$acr_name" --query id -o tsv)

        az role assignment create \
            --assignee "$SP_OBJECT_ID" \
            --role "AcrPull" \
            --scope "$ACR_ID" \
            2>/dev/null || print_warning "Role assignment may already exist"

        print_success "ACR pull access granted to $acr_name"
    else
        print_warning "ACR $acr_name does not exist"
    fi
done

# =============================================================================
# Step 5: Summary
# =============================================================================
print_header "Step 5: Summary & Next Steps"

cat <<EOF

✅ Managed Identities Setup Complete!

Created Resources:
------------------
1. Service Principal: $SP_NAME
   - App ID: $SP_APP_ID
   - Object ID: $SP_OBJECT_ID
   - Roles: Contributor on subscription, Key Vault Secrets User, AcrPull

2. Managed Identities for ACI:
   - dbt-aci-dev-identity (for dev container)
   - dbt-aci-uat-identity (for uat container)

GitHub Secrets to Configure:
-----------------------------
Go to: https://github.com/YOUR_REPO/settings/secrets/actions

Set these repository secrets:

AZURE_CREDENTIALS (paste entire JSON from above)
AZURE_CLIENT_ID: $SP_CLIENT_ID
AZURE_CLIENT_SECRET: $SP_CLIENT_SECRET
AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID
AZURE_TENANT_ID: $SP_TENANT_ID

ACR Credentials (get from Azure):
---------------------------------
For each environment:

az acr credential show --name dbtjobsdev
az acr credential show --name dbtjobsuat

Set as:
REGISTRY_USERNAME_DEV: <username from above>
REGISTRY_PASSWORD_DEV: <password from above>
REGISTRY_USERNAME_UAT: <username from above>
REGISTRY_PASSWORD_UAT: <password from above>

GitHub Environments:
-------------------
Create environments with protection rules:

1. dev environment:
   - No protection rules (auto-deploy)

2. uat environment:
   - Required reviewers: 1
   - Deployment branches: Only tags matching rel-*-uat

Terraform Configuration:
------------------------
Update your Terraform to use managed identities:

resource "azurerm_container_group" "aci" {
  ...

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.aci.id
    ]
  }

  container {
    ...
    environment_variables = {
      AZURE_CLIENT_ID = azurerm_user_assigned_identity.aci.client_id
    }
  }
}

Next Steps:
-----------
1. ✅ Set GitHub Secrets (see above)
2. ✅ Create GitHub Environments (dev, uat)
3. ✅ Update Terraform to reference managed identities
4. ✅ Generate Snowflake RSA keys and upload to Key Vault
5. ✅ Deploy Terraform infrastructure
6. ✅ Test deployment flow

Documentation:
--------------
Credentials saved to: .secrets/github-sp-credentials.json
⚠️  IMPORTANT: Add .secrets/ to .gitignore!

EOF

print_success "Setup complete! Follow the steps above to configure GitHub."
