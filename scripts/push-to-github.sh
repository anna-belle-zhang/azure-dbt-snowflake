#!/bin/bash
set -euo pipefail

# =============================================================================
# Push Trunk-Based Development Changes to GitHub
# =============================================================================
# This script commits and pushes all trunk-based development infrastructure
# changes to the GitHub repository
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

# =============================================================================
# Step 1: Verify Git Repository
# =============================================================================
print_header "Step 1: Verifying Git Repository"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not a git repository"
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)
print_info "Current branch: $CURRENT_BRANCH"

if [ "$CURRENT_BRANCH" != "main" ]; then
    print_warning "Not on main branch"
    read -p "Continue on branch '$CURRENT_BRANCH'? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Cancelled by user"
        exit 0
    fi
fi

# =============================================================================
# Step 2: Show Current Changes
# =============================================================================
print_header "Step 2: Current Changes"

echo "Modified files:"
git status --short

echo ""
echo "Detailed status:"
git status

# =============================================================================
# Step 3: Review Changes Summary
# =============================================================================
print_header "Step 3: Changes Summary"

cat <<'EOF'

Changes to be committed:
------------------------

Phase 1: Release Configuration Structure
  ✅ release/dev.yaml - Dev environment config (auto-deploy)
  ✅ release/uat.yaml - UAT environment config (manual deploy)
  ✅ release/prd.yaml - Production environment config (multi-approval)

Phase 2: DBT Configuration Updates
  ✅ tpch_transform/profiles.yml - Three parameterized profiles (dev/uat/prd)
  ✅ tpch_transform/entrypoint.sh - Environment-aware DBT execution

Phase 3: CI/CD Workflows
  ✅ .github/workflows/deploy-dev.yml - Auto-deploy to dev on main push
  ✅ .github/workflows/deploy-uat.yml - Manual deploy to UAT on rel-*-uat tag
  ✅ .github/workflows/deploy-prd.yml - Manual deploy to PRD on rel-*-prd tag

Phase 4: Helper Scripts
  ✅ scripts/validate-names.sh - Resource name validation
  ✅ scripts/check-azure-resources.sh - Azure availability checker
  ✅ scripts/create-azure-baseline.sh - Baseline resource creator
  ✅ scripts/README.md - Scripts documentation

Architecture:
-------------
- Trunk-based development (single main branch)
- Environment-locked release configs (release/*.yaml)
- Tag-based deployments (rel-YYYY-MM-DD-N-{uat|prd})
- Separate Azure resources per environment (ACR, Key Vault, Storage)
- Separate Snowflake accounts per environment

EOF

# =============================================================================
# Step 4: Confirm Push
# =============================================================================
print_header "Step 4: Confirm Changes"

read -p "Review the changes above. Do you want to proceed with commit and push? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    print_warning "Cancelled by user"
    exit 0
fi

# =============================================================================
# Step 5: Stage Changes
# =============================================================================
print_header "Step 5: Staging Changes"

print_info "Adding all changes..."
git add .

echo ""
echo "Staged files:"
git status --short

# =============================================================================
# Step 6: Create Commit
# =============================================================================
print_header "Step 6: Creating Commit"

# Create comprehensive commit message
COMMIT_MSG=$(cat <<'EOF'
Implement trunk-based development with environment-locked release configs

## Overview
Transformed single-environment deployment into trunk-based development with
three isolated environments (dev, uat, prd) using environment-locked release
configurations.

## Phase 1: Release Configuration Structure
- Created release/ directory with environment configs
- release/dev.yaml: Auto-deploy config (uses 'latest' image)
- release/uat.yaml: Manual deploy config (uses tested release tags)
- release/prd.yaml: Production config (multi-approval required)

## Phase 2: DBT Configuration Updates
- Updated tpch_transform/profiles.yml with three parameterized profiles
  - dev: Local development with ~/.ssh key
  - uat: Container execution with UAT Snowflake account
  - prd: Container execution with PRD Snowflake account
- Enhanced tpch_transform/entrypoint.sh
  - Parameterized DBT_TARGET environment variable
  - Added comprehensive error handling and logging
  - Support for DBT_FULL_REFRESH and DBT_SELECT options

## Phase 3: CI/CD Workflows
- .github/workflows/deploy-dev.yml: Auto-deploy to dev on every push to main
- .github/workflows/deploy-uat.yml: Manual deploy to UAT on rel-*-uat tag
- .github/workflows/deploy-prd.yml: Manual deploy to PRD on rel-*-prd tag
- Each workflow parses release/*.yaml for environment-specific settings
- Image promotion: dev → uat → prd with validation at each stage

## Phase 4: Helper Scripts
- scripts/validate-names.sh: Validates resource naming conventions
- scripts/check-azure-resources.sh: Checks Azure resource availability & quotas
- scripts/create-azure-baseline.sh: Creates baseline Azure resources
- scripts/README.md: Comprehensive scripts documentation

## Architecture Changes
- Single main branch (trunk-based development)
- Tag-based releases: rel-YYYY-MM-DD-N-{uat|prd}
- Environment isolation:
  - Separate Snowflake accounts (sf-dev, sf-uat, sf-prd)
  - Separate Azure infrastructure (ACR, Key Vault, Storage per env)
- Audit-friendly: Every deployment traceable to release config + git tag

## Deployment Flow
1. Developer pushes to main → Auto-deploys to dev
2. Update release/uat.yaml with tested image → Tag rel-*-uat → Approve
3. Update release/prd.yaml with UAT-tested image → Tag rel-*-prd → 2+ approvals

## Cost Estimate
- 3x ACR (Basic/Standard): ~$15-$40/month
- 3x Key Vault (Standard): ~$5/month
- 3x Storage Account: ~$2/month
- 3x ACI (job-based): ~$5/month
- Total: ~$27-$52 USD/month

## Next Steps (Manual)
1. Create Terraform environment directories (baseline-{env}/, infra-{env}/)
2. Generate Snowflake RSA keys per environment
3. Create Snowflake resources (databases, warehouses, roles, users)
4. Upload certificates to Key Vault
5. Configure GitHub Secrets and Environments
6. Deploy Terraform infrastructure

## References
- Implementation plan: /root/.claude/plans/distributed-foraging-moonbeam.md
- Azure Subscription: Visual Studio Professional (Blackwoods Australia)
- Subscription ID: ddfe89b6-c4e5-4d13-a3c0-441f618f19f7

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)

echo "Commit message:"
echo "----------------------------------------"
echo "$COMMIT_MSG"
echo "----------------------------------------"
echo ""

git commit -m "$COMMIT_MSG"

print_success "Commit created successfully"

# Show commit info
echo ""
git log -1 --stat

# =============================================================================
# Step 7: Push to Remote
# =============================================================================
print_header "Step 7: Pushing to GitHub"

print_info "Remote information:"
git remote -v

echo ""
read -p "Push to origin/$CURRENT_BRANCH? (yes/no): " confirm_push

if [ "$confirm_push" != "yes" ]; then
    print_warning "Commit created but not pushed"
    print_info "To push later, run: git push origin $CURRENT_BRANCH"
    exit 0
fi

print_info "Pushing to origin/$CURRENT_BRANCH..."
git push origin "$CURRENT_BRANCH"

print_success "Successfully pushed to GitHub!"

# =============================================================================
# Step 8: Summary
# =============================================================================
print_header "Step 8: Summary & Next Steps"

COMMIT_SHA=$(git rev-parse --short HEAD)

cat <<EOF

✅ Changes pushed successfully!

Commit: $COMMIT_SHA
Branch: $CURRENT_BRANCH
Remote: $(git remote get-url origin)

What happens next:
------------------
1. ⚠️  The deploy-dev.yml workflow will NOT trigger yet because:
   - infra-dev/ directory doesn't exist yet
   - Terraform will fail without environment-specific configs

2. 📋 Complete remaining setup tasks:

   a) Create Terraform environment directories:
      - Copy baseline/ → baseline-dev/, baseline-uat/, baseline-prd/
      - Copy infra/ → infra-dev/, infra-uat/, infra-prd/
      - Update backend.tf and .auto.tfvars per environment

   b) Configure GitHub:
      - Settings → Secrets → Add AZURE_CREDENTIALS, ACR credentials, etc.
      - Settings → Environments → Create dev, uat, prd with protection rules

   c) Setup Snowflake:
      - Generate RSA keys: openssl genrsa -out snowflake_dev.p8 2048
      - Create databases, warehouses, roles, users (per environment)
      - Upload certificates to Key Vault

   d) Deploy Terraform:
      - cd baseline-dev && terraform init && terraform apply
      - cd infra-dev && terraform init && terraform apply
      - Repeat for uat and prd

3. 🚀 Test the deployment flow:
   - Make a small change → push to main → verify dev auto-deploys
   - Tag rel-2026-01-09-1-uat → verify UAT deployment
   - Tag rel-2026-01-09-1-prd → verify PRD deployment with 2+ approvals

Documentation:
--------------
- Plan file: /root/.claude/plans/distributed-foraging-moonbeam.md
- Scripts README: scripts/README.md
- Release configs: release/dev.yaml, release/uat.yaml, release/prd.yaml

EOF

print_success "Trunk-based development infrastructure is now in GitHub!"
print_info "Review the commit: https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/commit/$COMMIT_SHA"
