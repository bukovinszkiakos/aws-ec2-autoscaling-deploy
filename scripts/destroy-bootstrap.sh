#!/usr/bin/env bash
# Final teardown of the Beacon project bootstrap infrastructure.
# Run only after the main application stack has been destroyed via the Destroy workflow.
#
# Removes:  ECR beacon-api, IAM beacon-github-actions + attached policies,
#           S3 beacon-tfstate-554422868760 (all object versions and delete markers).
# Preserves: GitHub OIDC provider token.actions.githubusercontent.com
#             (it is a data-source lookup — not owned by this Terraform stack,
#             never created or deleted by terraform apply/destroy).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUCKET="beacon-tfstate-554422868760"
export AWS_DEFAULT_REGION="eu-central-1"

# ── Prerequisites ─────────────────────────────────────────────────────────────

for cmd in terraform aws python3; do
  command -v "$cmd" >/dev/null || { echo "Error: '$cmd' not found in PATH." >&2; exit 1; }
done

# ── Verify AWS account ────────────────────────────────────────────────────────

ACTUAL=$(aws sts get-caller-identity --query Account --output text) \
  || { echo "Error: AWS credentials not configured or invalid." >&2; exit 1; }
[ "$ACTUAL" = "554422868760" ] \
  || { echo "Error: Wrong AWS account ($ACTUAL). Expected 554422868760." >&2; exit 1; }

# ── Verify the main stack has been destroyed ──────────────────────────────────

# Download the main Terraform state from S3 and confirm it has no managed resources.
# This is the authoritative check that the application infrastructure is gone.
TMPSTATE=$(mktemp)
trap 'rm -f "$TMPSTATE"' EXIT

aws s3 cp "s3://${BUCKET}/beacon/infra.tfstate" "$TMPSTATE" --no-progress \
  || { echo "Error: Cannot read main state from s3://${BUCKET}." >&2; exit 1; }

MANAGED=$(python3 -c "
import sys, json
s = json.load(open(sys.argv[1]))
print(sum(1 for r in s.get('resources', []) if r.get('mode') == 'managed'))
" "$TMPSTATE") \
  || { echo "Error: Failed to parse main Terraform state." >&2; exit 1; }

[ "$MANAGED" = "0" ] \
  || { echo "Error: Main stack still has $MANAGED resource(s). Run the Destroy workflow first." >&2; exit 1; }
echo "[OK] Main Terraform state is empty."

# ── Verify bootstrap state file exists ───────────────────────────────────────

[ -f "bootstrap/terraform.tfstate" ] \
  || { echo "Error: bootstrap/terraform.tfstate not found. Run from the repository root." >&2; exit 1; }

# ── Verify OIDC provider is not managed by this stack ────────────────────────
# If create_oidc_provider were true in terraform.tfvars, terraform destroy would
# delete the shared GitHub OIDC provider. Abort rather than proceed unsafely.

BOOTSTRAP_RESOURCES=$(terraform -chdir=bootstrap state list) \
  || { echo "Error: Failed to read bootstrap Terraform state." >&2; exit 1; }
if echo "$BOOTSTRAP_RESOURCES" | grep -q '^aws_iam_openid_connect_provider\.github'; then
  echo "Error: aws_iam_openid_connect_provider.github is a managed resource in the bootstrap state." >&2
  echo "       Set create_oidc_provider = false in terraform.tfvars before running this script." >&2
  exit 1
fi
echo "[OK] OIDC provider is not managed by this stack."

# ── Check for orphaned main-stack resources ───────────────────────────────────
# The Terraform state check above reflects what Terraform knows, but the state
# can be stale if the Destroy workflow failed partway through. These read-only
# AWS API calls verify the live environment. Any API failure aborts the script.

echo "Checking for orphaned main-stack resources..."

ASG_COUNT=$(aws autoscaling describe-auto-scaling-groups \
  --filters "Name=tag:Project,Values=beacon" \
  --query 'length(AutoScalingGroups)' --output text) \
  || { echo "Error: AWS API error querying Auto Scaling Groups." >&2; exit 1; }
[ "$ASG_COUNT" = "0" ] \
  || { echo "Error: $ASG_COUNT Auto Scaling Group(s) tagged Project=beacon still exist. Destroy the main stack first." >&2; exit 1; }

EC2_COUNT=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=beacon" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
  --query 'length(Reservations[].Instances[])' --output text) \
  || { echo "Error: AWS API error querying EC2 instances." >&2; exit 1; }
[ "$EC2_COUNT" = "0" ] \
  || { echo "Error: $EC2_COUNT EC2 instance(s) tagged Project=beacon still exist." >&2; exit 1; }

ALB_COUNT=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Project,Values=beacon" \
  --resource-type-filters "elasticloadbalancing:loadbalancer" \
  --query 'length(ResourceTagMappingList)' --output text) \
  || { echo "Error: AWS API error querying load balancers." >&2; exit 1; }
[ "$ALB_COUNT" = "0" ] \
  || { echo "Error: $ALB_COUNT load balancer(s) tagged Project=beacon still exist." >&2; exit 1; }

NAT_COUNT=$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:Project,Values=beacon" \
           "Name=state,Values=pending,available,deleting" \
  --query 'length(NatGateways)' --output text) \
  || { echo "Error: AWS API error querying NAT Gateways." >&2; exit 1; }
[ "$NAT_COUNT" = "0" ] \
  || { echo "Error: $NAT_COUNT NAT Gateway(s) tagged Project=beacon still exist." >&2; exit 1; }

EIP_COUNT=$(aws ec2 describe-addresses \
  --filters "Name=tag:Project,Values=beacon" \
  --query 'length(Addresses)' --output text) \
  || { echo "Error: AWS API error querying Elastic IPs." >&2; exit 1; }
[ "$EIP_COUNT" = "0" ] \
  || { echo "Error: $EIP_COUNT Elastic IP(s) tagged Project=beacon still exist." >&2; exit 1; }

echo "[OK] No orphaned main-stack resources found in AWS."

# ── Confirm ───────────────────────────────────────────────────────────────────

printf '\nThis will permanently delete:\n'
printf '  ECR:  beacon-api (force_delete removes all images)\n'
printf '  IAM:  beacon-github-actions role + all attached policies\n'
printf '  S3:   %s (all object versions)\n' "$BUCKET"
printf 'The shared GitHub OIDC provider will NOT be deleted.\n\n'
printf "Type 'destroy-bootstrap' to confirm: "
read -r INPUT
[ "$INPUT" = "destroy-bootstrap" ] \
  || { echo "Aborting." >&2; exit 1; }

# ── Purge S3 object versions and delete markers ───────────────────────────────
#
# A versioned S3 bucket cannot be deleted while it contains object versions or
# delete markers. aws s3 rb --force does not remove these. Versions are deleted
# in batches of 1000 (the delete-objects API limit). Each batch response is
# checked for per-object S3 errors in addition to CLI-level failures.

printf '\nPurging S3 object versions and delete markers...\n'
python3 - "$BUCKET" <<'PYEOF'
import sys, json, subprocess
bucket = sys.argv[1]
r = subprocess.run(["aws", "s3api", "list-object-versions", "--bucket", bucket],
                   capture_output=True, text=True, check=True)
data = json.loads(r.stdout) if r.stdout.strip() else {}
objects = [{"Key": o["Key"], "VersionId": o["VersionId"]}
           for o in data.get("Versions", []) + data.get("DeleteMarkers", [])]
if not objects:
    print("Bucket already empty.")
    sys.exit(0)
# delete-objects accepts at most 1000 objects per request.
for i in range(0, len(objects), 1000):
    batch = objects[i : i + 1000]
    r = subprocess.run(
        ["aws", "s3api", "delete-objects", "--bucket", bucket,
         "--delete", json.dumps({"Objects": batch, "Quiet": True})],
        capture_output=True, text=True, check=True)
    resp = json.loads(r.stdout) if r.stdout.strip() else {}
    errors = resp.get("Errors", [])
    if errors:
        for e in errors:
            print(f"Failed: {e.get('Key')} ({e.get('VersionId')}): {e.get('Code')}", file=sys.stderr)
        sys.exit(1)
print(f"Purged {len(objects)} version(s)/delete-marker(s).")
PYEOF

# ── Remove S3 resources from Terraform state ──────────────────────────────────
#
# aws_s3_bucket.tfstate has prevent_destroy = true, which makes terraform destroy
# refuse to delete it. We remove the four S3-related resources from state so
# Terraform only destroys the ECR and IAM resources. The bucket is deleted
# directly afterwards. This step is idempotent: if the resources are already
# absent (re-run after a partial failure), the if-block is simply skipped.

printf '\nRemoving S3 resources from Terraform state...\n'
CURRENT_STATE=$(terraform -chdir=bootstrap state list) \
  || { echo "Error: Failed to query bootstrap Terraform state." >&2; exit 1; }
if echo "$CURRENT_STATE" | grep -q '^aws_s3_bucket\.tfstate'; then
  terraform -chdir=bootstrap state rm \
    aws_s3_bucket.tfstate \
    aws_s3_bucket_versioning.tfstate \
    aws_s3_bucket_server_side_encryption_configuration.tfstate \
    aws_s3_bucket_public_access_block.tfstate
fi

# ── Destroy remaining bootstrap resources via Terraform ───────────────────────

printf '\nRunning terraform destroy (ECR + IAM)...\n'
terraform -chdir=bootstrap init -input=false -upgrade=false
terraform -chdir=bootstrap destroy -auto-approve -input=false

# ── Delete the now-empty S3 bucket ───────────────────────────────────────────

printf '\nDeleting S3 bucket...\n'
if BUCKET_ERR=$(aws s3api head-bucket --bucket "$BUCKET" 2>&1); then
  aws s3 rb "s3://${BUCKET}"
  echo "S3 bucket deleted."
elif echo "$BUCKET_ERR" | grep -qE '(404|NoSuchBucket)'; then
  echo "S3 bucket already gone."
else
  echo "Error: Unexpected error checking S3 bucket status: $BUCKET_ERR" >&2
  exit 1
fi

printf '\nBootstrap teardown complete.\n'
printf 'Local state files (bootstrap/terraform.tfstate etc.) are gitignored\n'
printf 'and can be deleted manually if desired.\n'
