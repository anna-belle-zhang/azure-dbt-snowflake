#!/bin/bash
set -euo pipefail

# =============================================================================
# DBT Entrypoint Script - Environment-Aware
# =============================================================================
# This script runs in Azure Container Instances and:
# 1. Retrieves Snowflake certificate from Key Vault using managed identity
# 2. Decodes and writes certificate to expected path
# 3. Executes dbt run with environment-specific target
#
# Environment Variables (injected by Terraform):
#   - ENV_KV_URL: Key Vault URL (e.g., https://secrets-aci-dev.vault.azure.net)
#   - ENV_SNOW_SECRET: Secret name in Key Vault (e.g., snowflake-certificate-dev)
#   - DBT_TARGET: Profile target (dev/uat/prd) - defaults to 'dev'
#
# Optional Environment Variables:
#   - DBT_FULL_REFRESH: Set to 'true' to run full refresh
#   - DBT_SELECT: Model selection (e.g., 'staging+')
#   - DBT_EXCLUDE: Models to exclude
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "================================="
echo "DBT Job Starting"
echo "================================="

# =============================================================================
# Step 1: Validate Environment Variables
# =============================================================================
log_info "Validating environment variables..."

if [ -z "${ENV_KV_URL:-}" ]; then
    log_error "ENV_KV_URL is not set"
    exit 1
fi

if [ -z "${ENV_SNOW_SECRET:-}" ]; then
    log_error "ENV_SNOW_SECRET is not set"
    exit 1
fi

# Default to 'dev' if DBT_TARGET not set
DBT_TARGET="${DBT_TARGET:-dev}"
log_info "DBT_TARGET: $DBT_TARGET"

# Certificate path
CERT_PATH="/snowflake_dbt.pem"
CERT_BASE64="/snowflake_dbt.64"

# =============================================================================
# Step 2: Retrieve Snowflake Certificate from Key Vault
# =============================================================================
log_info "Retrieving Snowflake certificate from Key Vault..."

kv_url="$ENV_KV_URL/secrets/$ENV_SNOW_SECRET"
log_info "Key Vault URL: $kv_url"

# Get Azure managed identity token
log_info "Obtaining managed identity token..."
token_response=$(curl -s \
    'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' \
    -H "Metadata:true")

if [ $? -ne 0 ]; then
    log_error "Failed to obtain managed identity token"
    exit 1
fi

token=$(echo "$token_response" | jq -r '.access_token')

if [ -z "$token" ] || [ "$token" == "null" ]; then
    log_error "Failed to extract access token from response"
    echo "Response: $token_response"
    exit 1
fi

log_info "Managed identity token obtained successfully"

# Retrieve secret from Key Vault
log_info "Fetching secret from Key Vault..."
secret_response=$(curl -s "$kv_url/?api-version=2016-10-01" -H "Authorization: Bearer $token")

if [ $? -ne 0 ]; then
    log_error "Failed to retrieve secret from Key Vault"
    exit 1
fi

secret_value=$(echo "$secret_response" | jq -r '.value')

if [ -z "$secret_value" ] || [ "$secret_value" == "null" ]; then
    log_error "Failed to extract secret value"
    echo "Response: $secret_response"
    exit 1
fi

# Write base64-encoded secret to temp file
echo "$secret_value" > "$CERT_BASE64"
log_info "Base64 certificate written to $CERT_BASE64"

# Decode to PEM format
base64 -d "$CERT_BASE64" > "$CERT_PATH"

if [ $? -ne 0 ]; then
    log_error "Failed to decode certificate"
    exit 1
fi

log_info "Certificate decoded and written to $CERT_PATH"

# Verify certificate file exists and has content
if [ ! -s "$CERT_PATH" ]; then
    log_error "Certificate file is empty or does not exist"
    exit 1
fi

# Set secure permissions on certificate
chmod 600 "$CERT_PATH"
log_info "Certificate permissions set to 600"

# Clean up base64 file
rm -f "$CERT_BASE64"

# =============================================================================
# Step 3: Prepare DBT Command
# =============================================================================
log_info "Preparing DBT command..."

dbt_cmd="dbt run -t $DBT_TARGET"

# Add full refresh flag if set
if [ "${DBT_FULL_REFRESH:-false}" == "true" ]; then
    log_warn "Full refresh mode enabled"
    dbt_cmd="$dbt_cmd --full-refresh"
fi

# Add model selection if set
if [ -n "${DBT_SELECT:-}" ]; then
    log_info "Model selection: $DBT_SELECT"
    dbt_cmd="$dbt_cmd --select $DBT_SELECT"
fi

# Add model exclusion if set
if [ -n "${DBT_EXCLUDE:-}" ]; then
    log_info "Model exclusion: $DBT_EXCLUDE"
    dbt_cmd="$dbt_cmd --exclude $DBT_EXCLUDE"
fi

log_info "DBT command: $dbt_cmd"

# =============================================================================
# Step 4: Execute DBT
# =============================================================================
echo "================================="
log_info "Executing DBT job on environment: $DBT_TARGET"
echo "================================="

# Run dbt and capture exit code
eval "$dbt_cmd"
dbt_exit_code=$?

# =============================================================================
# Step 5: Clean Up and Report Status
# =============================================================================
log_info "Cleaning up certificate file..."
rm -f "$CERT_PATH"

echo "================================="
if [ $dbt_exit_code -eq 0 ]; then
    log_info "DBT job completed successfully"
    echo "Environment: $DBT_TARGET"
    echo "Status: SUCCESS"
else
    log_error "DBT job failed with exit code $dbt_exit_code"
    echo "Environment: $DBT_TARGET"
    echo "Status: FAILED"
fi
echo "================================="

exit $dbt_exit_code
