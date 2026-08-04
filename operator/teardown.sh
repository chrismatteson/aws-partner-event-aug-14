#!/usr/bin/env bash
# Rip down one attendee's workshop account: both CloudFormation stacks, PLUS the resources
# the devbox stack Retains/snapshots on delete (S3, ECR, EBS, Aurora) that otherwise linger
# and keep billing. Mirrors deploy.sh; region-scoped, so it never touches another region's
# devbox.
#
#   bash operator/teardown.sh
#
# Env (match what deploy.sh used):
#   AWS_PROFILE / AWS_REGION   target account + region (default region us-east-1)
#   DEVBOX_STACK               default flyte-devbox-workshop
#   SANDBOX_STACK              default kiro-sandbox
#   STAGING_BUCKET             default ${DEVBOX_STACK}-staging-<acct>-<region>
#   FORCE=yes                  skip the interactive confirmation (for scripted 40-account runs)

set -uo pipefail
export AWS_PAGER=""
REGION="${AWS_REGION:-us-east-1}"
DEVBOX_STACK="${DEVBOX_STACK:-flyte-devbox-workshop}"
SANDBOX_STACK="${SANDBOX_STACK:-kiro-sandbox}"
aws() { command aws --region "$REGION" --no-cli-pager "$@"; }
step() { echo ""; echo "==> $*"; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || {
    echo "No AWS credentials. Set AWS_PROFILE (and 'aws sso login')." >&2; exit 1; }
STAGING_BUCKET="${STAGING_BUCKET:-${DEVBOX_STACK}-staging-${ACCOUNT_ID}-${REGION}}"
WORKSHOP_BUCKET="${DEVBOX_STACK}-flyte-${ACCOUNT_ID}-${REGION}"

cat <<EOF
Account : $ACCOUNT_ID
Region  : $REGION
Will DELETE:
  stacks : $SANDBOX_STACK, $DEVBOX_STACK
  buckets: $WORKSHOP_BUCKET, $STAGING_BUCKET
  ECR    : every repository in $REGION (throwaway account)
  EBS    : volumes tagged for $DEVBOX_STACK
  RDS    : Aurora snapshots for $DEVBOX_STACK
This does NOT touch other regions or other stacks.
EOF
if [ "${FORCE:-}" != "yes" ]; then
    read -r -p "Type the account id ($ACCOUNT_ID) to confirm: " c
    [ "$c" = "$ACCOUNT_ID" ] || { echo "aborted."; exit 1; }
fi

# 1. Sandbox stack FIRST -- it attaches an inline policy to the devbox instance role and
#    owns the SSM params, the login user, and the ECR create-on-push template.
step "Deleting $SANDBOX_STACK..."
aws cloudformation delete-stack --stack-name "$SANDBOX_STACK"
aws cloudformation wait stack-delete-complete --stack-name "$SANDBOX_STACK" 2>/dev/null \
    && echo "   gone" || echo "   (already gone or wait timed out -- check the console)"

# 2. Devbox stack -- terminates EC2/ALB/Cognito; Retains S3/ECR/EBS; snapshots Aurora.
step "Deleting $DEVBOX_STACK... (a few minutes)"
aws cloudformation delete-stack --stack-name "$DEVBOX_STACK"
aws cloudformation wait stack-delete-complete --stack-name "$DEVBOX_STACK" 2>/dev/null \
    && echo "   gone" || echo "   (still deleting or errored -- check the console before continuing)"

# 3. Retained S3 buckets (empty then delete).
for b in "$WORKSHOP_BUCKET" "$STAGING_BUCKET"; do
    if aws s3api head-bucket --bucket "$b" 2>/dev/null; then
        step "Emptying + deleting bucket $b..."
        aws s3 rm "s3://$b" --recursive >/dev/null 2>&1
        aws s3api delete-bucket --bucket "$b" && echo "   deleted"
    fi
done

# 4. ECR repositories (the devbox repo + anything create-on-push made). This deletes ALL
#    repos in the region -- safe for a dedicated throwaway account; comment out if sharing one.
step "Deleting ECR repositories in $REGION..."
for r in $(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text 2>/dev/null); do
    aws ecr delete-repository --repository-name "$r" --force >/dev/null 2>&1 && echo "   deleted $r"
done

# 5. The Retained EBS data volume (becomes 'available' once the stack detaches it).
step "Deleting EBS volumes tagged for $DEVBOX_STACK..."
for v in $(aws ec2 describe-volumes \
        --query "Volumes[?Tags[?contains(Value,'$DEVBOX_STACK')]].VolumeId" --output text 2>/dev/null); do
    aws ec2 delete-volume --volume-id "$v" >/dev/null 2>&1 && echo "   deleted $v"
done

# 6. Aurora final snapshot(s) taken at stack delete.
step "Deleting Aurora snapshots for $DEVBOX_STACK..."
for s in $(aws rds describe-db-cluster-snapshots \
        --query "DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier,'$DEVBOX_STACK')].DBClusterSnapshotIdentifier" \
        --output text 2>/dev/null); do
    aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier "$s" >/dev/null 2>&1 && echo "   deleted $s"
done

echo ""
echo "Done. Left intact on purpose: the Route 53 hosted zone, and anything in other regions."
echo "Spot-check for stragglers: aws cloudformation describe-stacks --region $REGION 2>&1 | grep -i workshop"
