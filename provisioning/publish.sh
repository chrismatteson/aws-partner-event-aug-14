#!/usr/bin/env bash
# ONE-TIME build step for the pure-CloudFormation path (provisioning/root.yaml). Nested stacks
# need absolute S3 TemplateURLs, so this packages the vendored devbox template and uploads all
# three templates to an S3 bucket. Run it once (or whenever the templates change); then AWS /
# Workshop Studio deploys root.yaml into each account with TemplatesBaseUrl pointing here.
#
#   bash provisioning/publish.sh <s3-bucket> [s3-prefix]
#
# The bucket must be READABLE by the accounts that deploy root.yaml (public-read, or a bucket
# policy granting them). Workshop Studio typically hosts content in its own bucket.
set -euo pipefail
export AWS_PAGER=""
BUCKET="${1:?usage: bash provisioning/publish.sh <s3-bucket> [s3-prefix]}"
PREFIX="${2:-workshop-templates}"
REGION="${AWS_REGION:-us-east-1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Packaging the devbox template (uploads its nested children to s3://$BUCKET/$PREFIX/devbox)..."
aws cloudformation package --region "$REGION" \
  --template-file "$REPO_ROOT/provisioning/devbox-cfn/devbox/cloudformation/root.yaml" \
  --s3-bucket "$BUCKET" --s3-prefix "$PREFIX/devbox" \
  --output-template-file /tmp/devbox-root.packaged.yaml

echo "==> Uploading root.yaml, devbox-root.yaml, kiro-sandbox.yaml..."
aws s3 cp --region "$REGION" /tmp/devbox-root.packaged.yaml       "s3://$BUCKET/$PREFIX/devbox-root.yaml"
aws s3 cp --region "$REGION" "$REPO_ROOT/provisioning/kiro-sandbox.yaml" "s3://$BUCKET/$PREFIX/kiro-sandbox.yaml"
aws s3 cp --region "$REGION" "$REPO_ROOT/provisioning/root.yaml"        "s3://$BUCKET/$PREFIX/root.yaml"

BASE="https://$BUCKET.s3.$REGION.amazonaws.com/$PREFIX"
cat <<EOF

Published. TemplatesBaseUrl:
  $BASE

Deploy into an attendee account (or point Workshop Studio at $BASE/root.yaml):

  aws cloudformation deploy --stack-name workshop --region $REGION \\
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \\
    --template-file $REPO_ROOT/provisioning/root.yaml \\
    --parameter-overrides \\
      TemplatesBaseUrl=$BASE \\
      DevboxAmiId=ami-xxxxxxxx \\
      DelegatorRoleArn=arn:aws:iam::<parent-acct>:role/flytedemo-delegator \\
      DelegationExternalId=<secret>

Outputs (KiroSandboxRoleArn, FlyteUiUrl, FlytePassword, KiroStatus, ...) are the handout.
EOF
