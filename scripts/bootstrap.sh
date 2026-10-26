#!/usr/bin/env bash
# Configures GitHub repository Variables and the production environment after
# the Beacon bootstrap Terraform stack has been applied.
#
# Phase 1 — bootstrap not yet applied:
#   Initialises the bootstrap directory, shows terraform plan, and exits.
#   No GitHub resources are created or modified.
#
# Phase 2 — bootstrap already applied:
#   Reads Terraform outputs and sets the four required GitHub Variables.
#   Creates the production environment if it does not exist.
#
# Usage:
#   chmod +x scripts/bootstrap.sh   # first time only
#   ./scripts/bootstrap.sh
#
# Prerequisites: terraform >= 1.11, aws CLI, gh CLI (authenticated)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ── Helpers ───────────────────────────────────────────────────────────────────
fail() { printf '\n[ERROR] %s\n' "$1" >&2; exit 1; }
ok()   { printf '[OK]    %s\n' "$1"; }
step() { printf '\n>>> %s\n' "$1"; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
step "Checking prerequisites"
for cmd in terraform aws gh; do
  command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' is not installed or not in PATH."
  ok "$cmd found"
done

# ── AWS authentication ────────────────────────────────────────────────────────
step "Validating AWS credentials"
aws sts get-caller-identity --output text >/dev/null 2>&1 \
  || fail "AWS credentials not configured or invalid. Run: aws configure"
ok "AWS credentials valid"

# ── GitHub CLI authentication ─────────────────────────────────────────────────
step "Validating GitHub CLI"
gh auth status >/dev/null 2>&1 \
  || fail "GitHub CLI not authenticated. Run: gh auth login"
ok "GitHub CLI authenticated"

# ── Bootstrap configuration ───────────────────────────────────────────────────
step "Checking bootstrap configuration"
[ -f "bootstrap/terraform.tfvars" ] \
  || fail "bootstrap/terraform.tfvars not found. Copy bootstrap/terraform.tfvars.example, set create_oidc_provider = true, and rerun."
ok "bootstrap/terraform.tfvars present"

# ── Terraform init ────────────────────────────────────────────────────────────
if [ ! -d "bootstrap/.terraform" ]; then
  step "Initialising Terraform (bootstrap)"
  terraform -chdir=bootstrap init -input=false
fi

# ── Detect whether bootstrap has been applied ─────────────────────────────────
step "Checking bootstrap Terraform state"
ROLE_ARN="$(terraform -chdir=bootstrap output -raw github_actions_role_arn 2>/dev/null)"

# ── Phase 1: not yet applied ───────────────────────────────────────────────────
if [ -z "$ROLE_ARN" ]; then
  step "Running terraform plan (bootstrap)"
  terraform -chdir=bootstrap plan -input=false

  printf '\n'
  printf '============================================================\n'
  printf '  Review the plan above.\n'
  printf '\n'
  printf '  The bootstrap stack has not been applied yet.\n'
  printf '  This script will not modify GitHub until the\n'
  printf '  infrastructure exists in Terraform state.\n'
  printf '\n'
  printf '  When you are ready to apply:\n'
  printf '\n'
  printf '    terraform -chdir=bootstrap apply\n'
  printf '\n'
  printf '  Then rerun this script:\n'
  printf '\n'
  printf '    ./scripts/bootstrap.sh\n'
  printf '============================================================\n'
  exit 0
fi

# ── Phase 2: bootstrap applied — read outputs ─────────────────────────────────
ok "Bootstrap state found"

step "Reading Terraform outputs"
STATE_BUCKET="$(terraform -chdir=bootstrap output -raw state_bucket_name)"
ECR_REPO="$(terraform -chdir=bootstrap output -raw ecr_repository_name)"
ok "github_actions_role_arn  ->  $ROLE_ARN"
ok "state_bucket_name        ->  $STATE_BUCKET"
ok "ecr_repository_name      ->  $ECR_REPO"

# Determine AWS_REGION: read from bootstrap/terraform.tfvars if explicitly set
# there, otherwise fall back to the default declared in bootstrap/variables.tf.
AWS_REGION=""
if grep -qE '^\s*aws_region\s*=' bootstrap/terraform.tfvars 2>/dev/null; then
  AWS_REGION="$(grep -E '^\s*aws_region\s*=' bootstrap/terraform.tfvars \
    | grep -v '^\s*#' \
    | sed 's/.*=\s*"\([^"]*\)".*/\1/' \
    | head -1)"
fi
if [ -z "$AWS_REGION" ]; then
  AWS_REGION="$(grep -A5 'variable "aws_region"' bootstrap/variables.tf \
    | grep -E '^\s*default\s*=' \
    | sed 's/.*=\s*"\([^"]*\)".*/\1/' \
    | head -1)"
fi
[ -n "$AWS_REGION" ] \
  || fail "Cannot determine AWS_REGION from bootstrap/terraform.tfvars or bootstrap/variables.tf."
ok "aws_region               ->  $AWS_REGION"

# ── Set GitHub Variables ──────────────────────────────────────────────────────
step "Setting GitHub repository variables"
gh variable set AWS_ROLE_ARN    --body "$ROLE_ARN"
ok "AWS_ROLE_ARN    set"
gh variable set TF_STATE_BUCKET --body "$STATE_BUCKET"
ok "TF_STATE_BUCKET set"
gh variable set ECR_REPOSITORY  --body "$ECR_REPO"
ok "ECR_REPOSITORY  set"
gh variable set AWS_REGION      --body "$AWS_REGION"
ok "AWS_REGION      set"

# ── Create production environment ─────────────────────────────────────────────
step "Creating production environment"
GITHUB_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# GET the environment; capture the full --include output, then extract the
# LAST HTTP status line so intermediate redirects do not yield a false status.
ENV_RC=0
ENV_OUT=""
ENV_OUT="$(gh api --include "repos/${GITHUB_REPO}/environments/production" 2>/dev/null)" \
  || ENV_RC=$?
ENV_STATUS="$(printf '%s' "$ENV_OUT" | awk '/^HTTP\// {status=$2} END {print status}')"

if [ "$ENV_STATUS" = "200" ]; then
  ok "production environment already exists — protection rules left untouched"
elif [ "$ENV_STATUS" = "404" ]; then
  gh api --method PUT "repos/${GITHUB_REPO}/environments/production" \
    --input /dev/null > /dev/null
  ok "production environment created"
elif [ -n "$ENV_STATUS" ]; then
  fail "GitHub API error when checking production environment (HTTP ${ENV_STATUS}). Verify GitHub authentication and repository permissions."
else
  fail "GitHub API unreachable when checking production environment (exit ${ENV_RC}). Check network connectivity and GitHub CLI authentication."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n'
printf '============================================================\n'
printf '  Bootstrap configuration complete.\n'
printf '\n'
printf '  GitHub variables set:\n'
printf '    AWS_ROLE_ARN    = %s\n' "$ROLE_ARN"
printf '    TF_STATE_BUCKET = %s\n' "$STATE_BUCKET"
printf '    ECR_REPOSITORY  = %s\n' "$ECR_REPO"
printf '    AWS_REGION      = %s\n' "$AWS_REGION"
printf '\n'
printf '  Environment: production (created or already exists)\n'
printf '\n'
printf '  DEPLOY_ENABLED has not been set. When you are ready to\n'
printf '  trigger the first deployment, set it explicitly:\n'
printf '\n'
printf '    gh variable set DEPLOY_ENABLED --body "true"\n'
printf '\n'
printf '  Then push a commit to main or dispatch the workflow:\n'
printf '\n'
printf '    gh workflow run deploy.yml\n'
printf '============================================================\n'
