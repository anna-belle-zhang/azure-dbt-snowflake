#!/bin/bash
set -euo pipefail

# =============================================================================
# Generate Environment-Specific Terraform Configurations
# =============================================================================
# This script creates baseline and infra Terraform configs for dev and uat
# based on values from release/*.yaml files
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

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check yq
if ! command -v yq &> /dev/null; then
    print_error "yq not found. Please install yq first."
    exit 1
fi

print_header "Generating Terraform Configurations for dev and uat"

# =============================================================================
# Function to create baseline Terraform for an environment
# =============================================================================
create_baseline_terraform() {
    local env=$1
    local config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi

    print_info "Creating baseline-${env}/ from release/${env}.yaml"

    # Extract values
    local location=$(yq '.azure.location' "$config_file")
    local rg_name=$(yq '.azure.resource_group' "$config_file")
    local acr_name=$(yq '.azure.acr_name' "$config_file")
    local acr_sku=$(yq '.azure.acr_sku' "$config_file")
    local kv_name=$(yq '.azure.keyvault_name' "$config_file")
    local kv_sku=$(yq '.azure.keyvault_sku' "$config_file")
    local storage_account=$(yq '.azure.storage_account_name' "$config_file")
    local storage_container=$(yq '.azure.storage_container_name' "$config_file")
    local baseline_state_key=$(yq '.azure.baseline_state_key' "$config_file")
    local soft_delete_days=$(yq '.azure.soft_delete_retention_days' "$config_file")
    local purge_protection=$(yq '.azure.purge_protection_enabled' "$config_file")

    # Create directory
    mkdir -p "$PROJECT_ROOT/baseline-${env}"

    # Create backend.tf
    cat > "$PROJECT_ROOT/baseline-${env}/backend.tf" <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "${rg_name}"
    storage_account_name = "${storage_account}"
    container_name       = "${storage_container}"
    key                  = "${baseline_state_key}"
  }
}
EOF

    # Create main.tf
    cat > "$PROJECT_ROOT/baseline-${env}/main.tf" <<EOF
provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = true
  tags                = var.tags
}

resource "azurerm_key_vault" "keyvault" {
  name                        = var.kv_name
  location                    = var.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  soft_delete_retention_days  = var.soft_delete_retention_days
  purge_protection_enabled    = var.purge_protection_enabled
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.kv_sku
  tags                        = var.tags
}

# User-assigned managed identity for ACI
resource "azurerm_user_assigned_identity" "aci" {
  name                = "dbt-aci-${env}-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

# Grant Key Vault Secrets User role to managed identity
resource "azurerm_role_assignment" "aci_kv_access" {
  scope                = azurerm_key_vault.keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aci.principal_id
}
EOF

    # Create variables.tf
    cat > "$PROJECT_ROOT/baseline-${env}/variables.tf" <<EOF
variable "location" {
  description = "Azure region"
  type        = string
}

variable "rg_name" {
  description = "Resource group name"
  type        = string
}

variable "acr_name" {
  description = "Container registry name"
  type        = string
}

variable "acr_sku" {
  description = "Container registry SKU"
  type        = string
  default     = "Basic"
}

variable "kv_name" {
  description = "Key Vault name"
  type        = string
}

variable "kv_sku" {
  description = "Key Vault SKU"
  type        = string
  default     = "standard"
}

variable "soft_delete_retention_days" {
  description = "Soft delete retention days"
  type        = number
  default     = 7
}

variable "purge_protection_enabled" {
  description = "Enable purge protection"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}
EOF

    # Create .auto.tfvars
    cat > "$PROJECT_ROOT/baseline-${env}/.auto.tfvars" <<EOF
location                   = "${location}"
rg_name                    = "${rg_name}"
acr_name                   = "${acr_name}"
acr_sku                    = "${acr_sku}"
kv_name                    = "${kv_name}"
kv_sku                     = "${kv_sku}"
soft_delete_retention_days = ${soft_delete_days}
purge_protection_enabled   = ${purge_protection}

tags = {
  provider                = "az"
  region                  = "euw"
  enterprise              = "syn"
  account                 = "${env}"
  system                  = "pract"
  environment             = "${env}"
  cmdb_name               = "dbt-pipeline-${env}"
  security_exposure_level = "MZ"
  status                  = "active"
  on_service              = "yes"
  managed_by              = "terraform"
  deployment_type         = "trunk-based"
}
EOF

    # Create outputs.tf
    cat > "$PROJECT_ROOT/baseline-${env}/outputs.tf" <<EOF
output "rg_name" {
  value = azurerm_resource_group.rg.name
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  value     = azurerm_container_registry.acr.admin_username
  sensitive = true
}

output "acr_admin_password" {
  value     = azurerm_container_registry.acr.admin_password
  sensitive = true
}

output "keyvault_name" {
  value = azurerm_key_vault.keyvault.name
}

output "keyvault_uri" {
  value = azurerm_key_vault.keyvault.vault_uri
}

output "managed_identity_id" {
  value = azurerm_user_assigned_identity.aci.id
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.aci.client_id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.aci.principal_id
}
EOF

    print_success "Created baseline-${env}/"
}

# =============================================================================
# Function to create infra Terraform for an environment
# =============================================================================
create_infra_terraform() {
    local env=$1
    local config_file="$PROJECT_ROOT/release/${env}.yaml"

    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi

    print_info "Creating infra-${env}/ from release/${env}.yaml"

    # Extract values
    local location=$(yq '.azure.location' "$config_file")
    local rg_name=$(yq '.azure.resource_group' "$config_file")
    local acr_name=$(yq '.azure.acr_name' "$config_file")
    local kv_name=$(yq '.azure.keyvault_name' "$config_file")
    local storage_account=$(yq '.azure.storage_account_name' "$config_file")
    local storage_container=$(yq '.azure.storage_container_name' "$config_file")
    local baseline_state_key=$(yq '.azure.baseline_state_key' "$config_file")
    local infra_state_key=$(yq '.azure.infra_state_key' "$config_file")
    local aci_name=$(yq '.aci.name' "$config_file")
    local aci_cpu=$(yq '.aci.cpu' "$config_file")
    local aci_memory=$(yq '.aci.memory' "$config_file")
    local dbt_target=$(yq '.dbt.target' "$config_file")
    local cert_secret_name=$(yq '.snowflake.certificate_secret_name' "$config_file")

    # Create directory
    mkdir -p "$PROJECT_ROOT/infra-${env}"

    # Create backend.tf
    cat > "$PROJECT_ROOT/infra-${env}/backend.tf" <<EOF
terraform {
  backend "azurerm" {
    resource_group_name  = "${rg_name}"
    storage_account_name = "${storage_account}"
    container_name       = "${storage_container}"
    key                  = "${infra_state_key}"
  }
}
EOF

    # Create main.tf
    cat > "$PROJECT_ROOT/infra-${env}/main.tf" <<EOF
provider "azurerm" {
  features {}
}

locals {
  image_name = "\${data.terraform_remote_state.azure_baseline.outputs.acr_login_server}/dbt/tpch_transform:\${var.image_version}"
}

data "terraform_remote_state" "azure_baseline" {
  backend = "azurerm"
  config = {
    resource_group_name  = "${rg_name}"
    storage_account_name = "${storage_account}"
    container_name       = "${storage_container}"
    key                  = "${baseline_state_key}"
  }
}

resource "azurerm_container_group" "aci" {
  name                = var.aci_name
  location            = var.location
  resource_group_name = var.rg_name
  ip_address_type     = "Public"
  os_type             = "Linux"
  restart_policy      = "Never"

  container {
    name   = "dbt"
    image  = local.image_name
    cpu    = var.cpu
    memory = var.memory

    ports {
      port     = 80
      protocol = "TCP"
    }

    environment_variables = {
      ENV_KV_URL      = var.keyvault_url
      ENV_SNOW_SECRET = var.cert_secret_name
      DBT_TARGET      = var.dbt_target
      AZURE_CLIENT_ID = data.terraform_remote_state.azure_baseline.outputs.managed_identity_client_id
    }
  }

  image_registry_credential {
    server   = data.terraform_remote_state.azure_baseline.outputs.acr_login_server
    username = data.terraform_remote_state.azure_baseline.outputs.acr_admin_username
    password = data.terraform_remote_state.azure_baseline.outputs.acr_admin_password
  }

  identity {
    type = "UserAssigned"
    identity_ids = [
      data.terraform_remote_state.azure_baseline.outputs.managed_identity_id
    ]
  }

  tags = var.tags
}
EOF

    # Create variables.tf
    cat > "$PROJECT_ROOT/infra-${env}/variables.tf" <<EOF
variable "location" {
  description = "Azure region"
  type        = string
}

variable "rg_name" {
  description = "Resource group name"
  type        = string
}

variable "aci_name" {
  description = "Container instance name"
  type        = string
}

variable "cpu" {
  description = "CPU cores"
  type        = string
  default     = "0.5"
}

variable "memory" {
  description = "Memory in GB"
  type        = string
  default     = "1"
}

variable "image_version" {
  description = "Docker image version (commit SHA or release tag)"
  type        = string
}

variable "dbt_target" {
  description = "DBT profile target (dev/uat/prd)"
  type        = string
}

variable "keyvault_url" {
  description = "Key Vault URL"
  type        = string
}

variable "cert_secret_name" {
  description = "Snowflake certificate secret name"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
}
EOF

    # Create .auto.tfvars
    cat > "$PROJECT_ROOT/infra-${env}/.auto.tfvars" <<EOF
location         = "${location}"
rg_name          = "${rg_name}"
aci_name         = "${aci_name}"
cpu              = "${aci_cpu}"
memory           = "${aci_memory}"
dbt_target       = "${dbt_target}"
keyvault_url     = "https://${kv_name}.vault.azure.net"
cert_secret_name = "${cert_secret_name}"

tags = {
  provider                = "az"
  region                  = "euw"
  enterprise              = "syn"
  account                 = "${env}"
  system                  = "pract"
  environment             = "${env}"
  cmdb_name               = "dbt-pipeline-${env}"
  security_exposure_level = "MZ"
  status                  = "active"
  on_service              = "yes"
  managed_by              = "terraform"
  deployment_type         = "trunk-based"
}
EOF

    # Create outputs.tf
    cat > "$PROJECT_ROOT/infra-${env}/outputs.tf" <<EOF
output "aci_id" {
  value = azurerm_container_group.aci.id
}

output "aci_fqdn" {
  value = azurerm_container_group.aci.fqdn
}

output "aci_ip_address" {
  value = azurerm_container_group.aci.ip_address
}
EOF

    print_success "Created infra-${env}/"
}

# =============================================================================
# Main execution
# =============================================================================

for env in dev uat; do
    create_baseline_terraform "$env"
    create_infra_terraform "$env"
done

print_header "Summary"

cat <<EOF

✅ Terraform configurations generated!

Created directories:
--------------------
baseline-dev/
  ├── backend.tf (state: ${storage_account}/dbt_dev_baseline.terraform.tfstate)
  ├── main.tf (ACR: dbtjobsdev, KV: secrets-aci-dev, Managed Identity)
  ├── variables.tf
  ├── .auto.tfvars
  └── outputs.tf

baseline-uat/
  ├── backend.tf (state: ${storage_account}/dbt_uat_baseline.terraform.tfstate)
  ├── main.tf (ACR: dbtjobsuat, KV: secrets-aci-uat, Managed Identity)
  ├── variables.tf
  ├── .auto.tfvars
  └── outputs.tf

infra-dev/
  ├── backend.tf (state: ${storage_account}/dbt_dev_infra.terraform.tfstate)
  ├── main.tf (ACI with user-assigned managed identity)
  ├── variables.tf
  ├── .auto.tfvars
  └── outputs.tf

infra-uat/
  ├── backend.tf (state: ${storage_account}/dbt_uat_infra.terraform.tfstate)
  ├── main.tf (ACI with user-assigned managed identity)
  ├── variables.tf
  ├── .auto.tfvars
  └── outputs.tf

Key Features:
-------------
✅ User-assigned managed identities (created in baseline)
✅ Key Vault RBAC for managed identities
✅ Environment-specific configurations
✅ Parameterized DBT_TARGET in ACI
✅ Separate Terraform state per environment

Next Steps:
-----------
1. Initialize and apply baseline Terraform:
   cd baseline-dev && terraform init && terraform apply
   cd ../baseline-uat && terraform init && terraform apply

2. Initialize and apply infra Terraform:
   cd infra-dev && terraform init && terraform apply -var='image_version=latest'
   cd ../infra-uat && terraform init && terraform apply -var='image_version=rel-2026-01-09-1'

3. Upload Snowflake certificates to Key Vault:
   az keyvault secret set --vault-name secrets-aci-dev --name snowflake-certificate-dev --file snowflake_dev.p8.b64
   az keyvault secret set --vault-name secrets-aci-uat --name snowflake-certificate-uat --file snowflake_uat.p8.b64

4. Test deployments via GitHub Actions

EOF

print_success "Terraform environment configurations ready!"
