#!/usr/bin/env bash
# Stand up one attendee's workshop account, end to end, with CloudFormation.
#
#   bash provisioning/deploy.sh <flyte-domain> <attendee-email> [llama-cloud-key]
#
# Example:
#   bash provisioning/deploy.sh student01.flytedemo.app you@example.com llx-abc123
#
# It runs two CloudFormation stacks -- the Flyte devbox (from the flyte-aws-marketplace
# template) and the Kiro provisioning (provisioning/kiro-sandbox.yaml) -- and prints the
# four values setup/00-kiro-web.md needs. There is nothing imperative here beyond wiring
# one stack's outputs into the next; both stacks are plain CloudFormation.
#
# Requirements:
#   * AWS CLI v2 with credentials for the TARGET account (set AWS_PROFILE / AWS_REGION).
#   * A Route 53 public hosted zone that <flyte-domain> sits under (auto-discovered).
#   * The devbox AMI published to SSM /flyte-devbox/ami/latest in the region.
#
# Knobs (env vars):
#   AWS_REGION       target region (default us-east-1 -- Kiro Web + Bedrock live here)
#   AUTOSTOP         Yes|No -- devbox idle auto-stop. DEFAULT No, so it never sleeps and
#                    there are no ~2-minute wake delays mid-workshop. Set AUTOSTOP=Yes to
#                    save money on a long-lived box (it stops after ~30 min idle, wakes on
#                    the next request).
#   DEVBOX_STACK     devbox stack name   (default flyte-devbox-workshop)
#   SANDBOX_STACK    provisioning stack  (default kiro-sandbox)
#   STAGING_BUCKET   S3 bucket for packaging the nested devbox template (auto-created)
#   DEVBOX_AMI_ID    explicit AMI id. Set this in a bare account that has nothing in SSM
#                    /flyte-devbox/ami/latest (e.g. a shared/public AMI); skips the SSM
#                    preflight and passes AmiId to the stack.
#   DELEGATION_URL   central delegation service endpoint (provisioning/delegation-service.yaml).
#   DELEGATION_TOKEN shared token for it. When both are set, deploy.sh creates a hosted zone
#                    for <flyte-domain> IN THIS account and delegates it from the parent via
#                    the service -- so a bare account needs no pre-existing zone. When unset,
#                    <flyte-domain> is assumed already resolvable (an existing zone).

set -euo pipefail
export AWS_PAGER=""

FLYTE_DOMAIN="${1:-}"
ATTENDEE_EMAIL="${2:-}"
LLAMA_KEY="${3:-}"
if [ -z "$FLYTE_DOMAIN" ] || [ -z "$ATTENDEE_EMAIL" ]; then
    echo "usage: bash provisioning/deploy.sh <flyte-domain> <attendee-email> [llama-cloud-key]" >&2
    exit 2
fi

REGION="${AWS_REGION:-us-east-1}"
AUTOSTOP="${AUTOSTOP:-No}"
DEVBOX_STACK="${DEVBOX_STACK:-flyte-devbox-workshop}"
SANDBOX_STACK="${SANDBOX_STACK:-kiro-sandbox}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

aws() { command aws --region "$REGION" --no-cli-pager "$@"; }
step() { echo ""; echo "==> $*"; }
fail() { echo ""; echo "ERROR: $*" >&2; exit 1; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) \
    || fail "No AWS credentials. Set AWS_PROFILE (and run 'aws sso login' if needed)."
echo "Account $ACCOUNT_ID, region $REGION, domain $FLYTE_DOMAIN, autostop $AUTOSTOP"

# --- preflight: the devbox AMI -----------------------------------------------------------
# The template's AmiSsmParameter is an SSM-typed parameter, so CloudFormation ALWAYS
# resolves /flyte-devbox/ami/latest at changeset time (even though AmiId can override it in
# the template). So in a bare account we must put that SSM param before deploying.
DEVBOX_AMI_ID="${DEVBOX_AMI_ID:-}"
if [ -n "$DEVBOX_AMI_ID" ]; then
    echo "Publishing AMI $DEVBOX_AMI_ID to SSM /flyte-devbox/ami/latest in this account..."
    aws ssm put-parameter --name /flyte-devbox/ami/latest --type String \
        --value "$DEVBOX_AMI_ID" --overwrite >/dev/null \
        || fail "Couldn't write the AMI to SSM /flyte-devbox/ami/latest."
else
    aws ssm get-parameter --name /flyte-devbox/ami/latest --query Parameter.Value --output text >/dev/null 2>&1 \
        || fail "SSM /flyte-devbox/ami/latest not found in $REGION, and DEVBOX_AMI_ID is unset. Either publish the AMI to SSM, or set DEVBOX_AMI_ID to a shared/public devbox AMI id."
fi

# --- DNS: ensure an in-account zone for the domain, delegated from the parent ------------
# The devbox's ACM cert and *.apps wildcard need <flyte-domain> publicly resolvable. In a
# bare account we create the hosted zone here and delegate ONE NS record from the central
# parent via the delegation service. Idempotent: an existing zone is reused.
ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$FLYTE_DOMAIN" \
    --query "HostedZones[?Name=='${FLYTE_DOMAIN}.'].Id | [0]" --output text 2>/dev/null)
if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "None" ]; then
    step "Creating hosted zone for $FLYTE_DOMAIN..."
    ZONE_ID=$(aws route53 create-hosted-zone --name "$FLYTE_DOMAIN" \
        --caller-reference "ws-${FLYTE_DOMAIN}-$$-${RANDOM}" \
        --query 'HostedZone.Id' --output text) || fail "couldn't create the hosted zone."
else
    echo "Reusing existing hosted zone $ZONE_ID for $FLYTE_DOMAIN."
fi
ZONE_NS=$(aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers' --output json)

if [ -n "${DELEGATION_URL:-}" ] && [ -n "${DELEGATION_TOKEN:-}" ]; then
    step "Delegating $FLYTE_DOMAIN via the delegation service..."
    DELEG_BODY=$(printf '{"token":"%s","subdomain":"%s","nameservers":%s}' \
        "$DELEGATION_TOKEN" "$FLYTE_DOMAIN" "$ZONE_NS")
    curl -fsS -X POST "$DELEGATION_URL" -H 'content-type: application/json' -d "$DELEG_BODY" \
        || fail "delegation call failed (check DELEGATION_URL / DELEGATION_TOKEN)."
    echo ""
    # Give the NS delegation a moment to propagate so ACM validation isn't slow to start.
    echo "   waiting ~30s for delegation to propagate..."; sleep 30
else
    echo "DELEGATION_URL/TOKEN not set -- assuming $FLYTE_DOMAIN is already delegated."
    echo "   (to delegate manually, add these NS to the parent zone for $FLYTE_DOMAIN:"
    echo "    $(echo "$ZONE_NS" | tr -d '[]\n" ' | tr ',' ' '))"
fi

# --- 1. devbox stack (vendored, nested template) ----------------------------------------
# The devbox CloudFormation is vendored under provisioning/devbox-cfn/ (from
# flyte-aws-marketplace, Apache-2.0) so this repo is self-contained and we can modify it.
DEVBOX_ROOT="$REPO_ROOT/provisioning/devbox-cfn/devbox/cloudformation/root.yaml"
[ -f "$DEVBOX_ROOT" ] || fail "Vendored devbox template not found at $DEVBOX_ROOT."

STAGING_BUCKET="${STAGING_BUCKET:-${DEVBOX_STACK}-staging-${ACCOUNT_ID}-${REGION}}"
if ! aws s3api head-bucket --bucket "$STAGING_BUCKET" 2>/dev/null; then
    step "Creating staging bucket $STAGING_BUCKET..."
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$STAGING_BUCKET" >/dev/null
    else
        aws s3api create-bucket --bucket "$STAGING_BUCKET" \
            --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
    fi
fi

step "Packaging + deploying the devbox stack ($DEVBOX_STACK)... (Prod mode: Aurora + ACM, ~5-10 min)"
PACKAGED=$(mktemp)
aws cloudformation package \
    --template-file "$DEVBOX_ROOT" \
    --s3-bucket "$STAGING_BUCKET" \
    --output-template-file "$PACKAGED" >/dev/null
# AmiId is left unset on purpose — the SSM param (written above in a bare account, or
# maintained by the AMI pipeline otherwise) is what the template resolves.
aws cloudformation deploy \
    --stack-name "$DEVBOX_STACK" \
    --template-file "$PACKAGED" \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides "Domain=$FLYTE_DOMAIN" "AutoStop=$AUTOSTOP"

# --- gather devbox outputs to feed the provisioning stack -------------------------------
step "Reading devbox outputs..."
dbout() { aws cloudformation describe-stacks --stack-name "$DEVBOX_STACK" \
            --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
POOL_ID=$(dbout CognitoUserPoolId)
CLIENT_ID=$(dbout CognitoM2MClientId)
[ -n "$POOL_ID" ] && [ -n "$CLIENT_ID" ] || fail "Devbox stack didn't output Cognito ids -- is it Prod mode (Domain set)?"

CLIENT_SECRET=$(aws cognito-idp describe-user-pool-client \
    --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" \
    --query 'UserPoolClient.ClientSecret' --output text)
COGNITO_PREFIX=$(aws cognito-idp describe-user-pool --user-pool-id "$POOL_ID" \
    --query 'UserPool.Domain' --output text)
COGNITO_DOMAIN="https://${COGNITO_PREFIX}.auth.${REGION}.amazoncognito.com"
INSTANCE_ROLE=$(aws iam list-roles \
    --query "Roles[?contains(RoleName,'${DEVBOX_STACK}') && contains(RoleName,'InstanceRole')].RoleName | [0]" \
    --output text)
[ -n "$INSTANCE_ROLE" ] && [ "$INSTANCE_ROLE" != "None" ] || fail "Couldn't find the devbox instance role."

# --- 2. provisioning stack (role + SSM + Cognito login + Bedrock + ECR) -----------------
step "Deploying the Kiro provisioning stack ($SANDBOX_STACK)..."
PARAMS=(
    "FlyteDomain=$FLYTE_DOMAIN"
    "CognitoDomain=$COGNITO_DOMAIN"
    "CognitoClientId=$CLIENT_ID"
    "CognitoClientSecret=$CLIENT_SECRET"
    "DevboxInstanceRoleName=$INSTANCE_ROLE"
    "CognitoUserPoolId=$POOL_ID"
    "AttendeeEmail=$ATTENDEE_EMAIL"
)
[ -n "$LLAMA_KEY" ] && PARAMS+=("LlamaCloudApiKey=$LLAMA_KEY")
aws cloudformation deploy \
    --stack-name "$SANDBOX_STACK" \
    --template-file "$REPO_ROOT/provisioning/kiro-sandbox.yaml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides "${PARAMS[@]}"

# --- the handout ------------------------------------------------------------------------
sbout() { aws cloudformation describe-stacks --stack-name "$SANDBOX_STACK" \
            --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
ROLE_ARN=$(sbout KiroSandboxRoleArn)
UI_URL=$(sbout FlyteUiUrl)
LOGIN_EMAIL=$(sbout FlyteLoginEmail)
LOGIN_PASS=$(sbout FlytePassword)
ALLOWLIST=".$(echo "$FLYTE_DOMAIN" | cut -d. -f2-), .amazoncognito.com"
MCP_ARGS="-y mcp-remote https://flyte-mcp.apps.demo.hosted.unionai.cloud/flyte-mcp/mcp"
cat <<EOF

================================================================================
  $FLYTE_DOMAIN is ready. Everything the attendee needs (see setup/):

  FLYTE CONSOLE  (the devbox UI -- where you verify executions)
    URL       : $UI_URL
    login     : $LOGIN_EMAIL
    password  : $LOGIN_PASS

  KIRO WEB  (the agent -- https://app.kiro.dev)
    Sandbox IAM Role ARN : $ROLE_ARN
      (paste at Settings > Agent > Sandbox > IAM Role)
    Network allow-list   : $ALLOWLIST
    MCP server (local)   : command 'npx', args '$MCP_ARGS'

  THEN, in a Kiro task:  Run bash scripts/bootstrap.sh
================================================================================
EOF
