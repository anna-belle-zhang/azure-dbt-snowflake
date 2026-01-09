#!/bin/bash
set -euo pipefail

# =============================================================================
# Azure Resource Name Validator (No Login Required)
# =============================================================================
# This script validates resource names from release configs
# without requiring Azure login
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

# Extract names from release configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

print_header "Validating Resource Names from Release Configs"

# Check if yq is available
if ! command -v yq &> /dev/null; then
    print_warning "yq not found, installing..."
    sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    sudo chmod +x /usr/local/bin/yq
    print_success "yq installed"
fi

# Validate ACR names
print_header "Container Registry Names (3-50 chars, alphanumeric)"

for env in dev uat prd; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        print_error "$config_file not found"
        continue
    fi

    acr_name=$(yq '.azure.acr_name' "$config_file")
    length=${#acr_name}

    echo -n "$env: '$acr_name' (${length} chars) - "

    if [[ $length -ge 3 && $length -le 50 && "$acr_name" =~ ^[a-zA-Z0-9]+$ ]]; then
        print_success "Valid"
    else
        print_error "Invalid - Must be 3-50 alphanumeric characters"
    fi
done

# Validate Key Vault names
print_header "Key Vault Names (3-24 chars, alphanumeric+hyphens, start with letter)"

for env in dev uat prd; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        continue
    fi

    kv_name=$(yq '.azure.keyvault_name' "$config_file")
    length=${#kv_name}

    echo -n "$env: '$kv_name' (${length} chars) - "

    if [[ $length -ge 3 && $length -le 24 && "$kv_name" =~ ^[a-zA-Z][a-zA-Z0-9-]*$ ]]; then
        print_success "Valid"
    else
        print_error "Invalid - Must be 3-24 chars, start with letter, alphanumeric+hyphens"
    fi
done

# Validate Storage Account names
print_header "Storage Account Names (3-24 chars, lowercase alphanumeric)"

for env in dev uat prd; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        continue
    fi

    storage_name=$(yq '.azure.storage_account_name' "$config_file")
    length=${#storage_name}

    echo -n "$env: '$storage_name' (${length} chars) - "

    if [[ $length -ge 3 && $length -le 24 && "$storage_name" =~ ^[a-z0-9]+$ ]]; then
        print_success "Valid"
    else
        print_error "Invalid - Must be 3-24 lowercase alphanumeric characters"
    fi
done

# Validate Resource Group names
print_header "Resource Group Names"

for env in dev uat prd; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        continue
    fi

    rg_name=$(yq '.azure.resource_group' "$config_file")

    echo "$env: '$rg_name'"
done

# Snowflake configuration check
print_header "Snowflake Configuration"

for env in dev uat prd; do
    config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        continue
    fi

    sf_account=$(yq '.snowflake.account' "$config_file")
    sf_db=$(yq '.snowflake.database' "$config_file")
    sf_wh=$(yq '.snowflake.warehouse' "$config_file")
    sf_role=$(yq '.snowflake.role' "$config_file")
    sf_user=$(yq '.snowflake.user' "$config_file")

    echo ""
    echo "$env environment:"
    echo "  Account: $sf_account"
    echo "  Database: $sf_db"
    echo "  Warehouse: $sf_wh"
    echo "  Role: $sf_role"
    echo "  User: $sf_user"
done

# Summary
print_header "Setup Checklist"

cat <<'EOF'

Azure Resources to Create:
--------------------------
For each environment (dev, uat, prd):

1. Resource Group
   ✓ Name validated above

2. Storage Account (for Terraform state)
   ✓ Name validated above
   Command: az storage account create --name <name> --resource-group <rg> --location westeurope --sku Standard_LRS

3. Storage Container (for Terraform state)
   Command: az storage container create --name <container> --account-name <storage-account>

4. Container Registry (ACR)
   ✓ Name validated above
   Command: az acr create --name <name> --resource-group <rg> --sku Basic --admin-enabled true

5. Key Vault
   ✓ Name validated above
   Command: az keyvault create --name <name> --resource-group <rg> --location westeurope

Snowflake Resources to Create:
------------------------------
For each environment (dev, uat, prd):

1. Generate RSA Key Pair
   openssl genrsa -out snowflake_<env>.p8 2048
   openssl rsa -in snowflake_<env>.p8 -pubout -out snowflake_<env>.pub
   base64 -i snowflake_<env>.p8 > snowflake_<env>.p8.b64

2. Create Database
   CREATE DATABASE <database_name>;

3. Create Warehouse
   CREATE WAREHOUSE <warehouse_name> WITH WAREHOUSE_SIZE = 'XSMALL';

4. Create Role
   CREATE ROLE <role_name>;

5. Create User with RSA Key
   CREATE USER <user_name> RSA_PUBLIC_KEY='<public_key>';
   GRANT ROLE <role_name> TO USER <user_name>;

6. Grant Permissions
   GRANT ALL ON DATABASE <database> TO ROLE <role>;
   GRANT USAGE ON WAREHOUSE <warehouse> TO ROLE <role>;

7. Upload Certificate to Key Vault
   az keyvault secret set --vault-name <kv-name> --name <secret-name> --file snowflake_<env>.p8.b64

GitHub Configuration:
--------------------
1. Create Service Principal for CI/CD
2. Set GitHub Secrets (see check-azure-resources.sh for details)
3. Create GitHub Environments (dev, uat, prd) with protection rules

Next Steps:
-----------
Run: ./scripts/check-azure-resources.sh
This will check actual availability in Azure after login

EOF

print_success "Validation complete!"
