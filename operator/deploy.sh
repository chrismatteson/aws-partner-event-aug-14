#!/usr/bin/env bash
# Stand up one attendee's workshop account, end to end, with CloudFormation.
#
#   bash operator/deploy.sh [flyte-domain] [llama-cloud-key]
#
# With NO domain (the Workshop-Studio case), it derives a unique, stable one from this
# account's id: s<8-hex-of-sha256(account-id)>.<PARENT_DOMAIN>. So the same command works
# unchanged in every attendee account, no per-account argument:
#   bash operator/deploy.sh
# Or pin the domain explicitly (testing):
#   bash operator/deploy.sh student01.flytedemo.app llx-abc123
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
# Delegation (deploy.sh creates a hosted zone for <flyte-domain> IN the target account, then
# delegates it from the parent zone). A locked-down Workshop Studio account can't reach a
# central Function URL (SCP-blocked) but CAN sts:AssumeRole, so the recommended path is:
#   DELEGATOR_ROLE_ARN + DELEGATION_EXTERNAL_ID   RECOMMENDED, needs NO central credentials.
#                    The attendee account assumes the central delegator role (deployed once via
#                    provisioning/delegator-role.yaml) with its OWN creds, gated by the
#                    external-id, and calls the role's guard Lambda -- which writes exactly one
#                    NS record in the parent zone and nothing else. The role ARN is not secret;
#                    the external-id is (inject it privately, never commit it). DELEGATOR_FUNCTION
#                    overrides the Lambda name (default flytedemo-delegator).
#   DELEGATION_PROFILE + DELEGATION_ZONE_ID       same-operator testing only: you also hold a
#                    profile for the parent account; deploy.sh writes the NS record directly.
#   (neither)        <flyte-domain> is assumed already resolvable; the NS are printed.

set -euo pipefail
export AWS_PAGER=""

FLYTE_DOMAIN="${1:-}"        # optional; if empty it's derived from the account id (below)
LLAMA_KEY="${2:-${LLAMA_CLOUD_API_KEY:-}}"
# AWS Workshop Studio assigns random participant logins, so we don't take an email as input.
# This is only the Cognito username for the Flyte console (a throwaway per-account pool) --
# generic by default; set ATTENDEE_EMAIL to override.
ATTENDEE_EMAIL="${ATTENDEE_EMAIL:-workshop@flytedemo.app}"
# When no domain is given, deploy.sh builds <label>.<PARENT_DOMAIN> where <label> is derived
# from this account's id -- unique, stable, and needs no central coordination (see below).
PARENT_DOMAIN="${PARENT_DOMAIN:-flytedemo.app}"

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

# Derive a unique, stable subdomain from the account id when one isn't given. Each attendee
# has their own account, so sha256(account-id) is collision-free and needs zero coordination
# (no counter, no central assignment, no races when many accounts deploy at once). Hashing
# (vs the raw id) keeps the 12-digit account id out of public DNS. Deterministic -> re-runs
# hit the same name. Matches the delegator guard's label pattern ^s[0-9a-f]{8}$.
if [ -z "$FLYTE_DOMAIN" ]; then
    _sha256hex() {
        if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
        elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
        else openssl dgst -sha256 | awk '{print $NF}'; fi
    }
    LABEL="s$(printf '%s' "$ACCOUNT_ID" | _sha256hex | cut -c1-8)"
    FLYTE_DOMAIN="${LABEL}.${PARENT_DOMAIN}"
    echo "No domain given -- derived from account id: $FLYTE_DOMAIN"
fi
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

if [ -n "${DELEGATOR_ROLE_ARN:-}" ]; then
    # RECOMMENDED cross-org path. The attendee account assumes the central delegator role with
    # ITS OWN credentials (no central creds in this deploy), gated by the external-id, then
    # calls the guard Lambda -- which writes exactly one NS record in the parent zone. Nothing
    # here can touch anything else in the parent zone.
    step "Delegating $FLYTE_DOMAIN via the central delegator role (assume-role)..."
    ASSUME=(--role-arn "$DELEGATOR_ROLE_ARN" --role-session-name "ws-deleg-${ACCOUNT_ID}")
    [ -n "${DELEGATION_EXTERNAL_ID:-}" ] && ASSUME+=(--external-id "$DELEGATION_EXTERNAL_ID")
    DCREDS=$(aws sts assume-role "${ASSUME[@]}" \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text) \
        || fail "couldn't assume DELEGATOR_ROLE_ARN (check the ARN + DELEGATION_EXTERNAL_ID)."
    read -r DAK DSK DST <<<"$DCREDS"
    DELEG_PAYLOAD=$(printf '{"subdomain":"%s","nameservers":%s}' "$FLYTE_DOMAIN" "$ZONE_NS")
    DELEG_OUT=$(mktemp)
    DELEG_META=$(AWS_ACCESS_KEY_ID="$DAK" AWS_SECRET_ACCESS_KEY="$DSK" AWS_SESSION_TOKEN="$DST" \
        aws lambda invoke --function-name "${DELEGATOR_FUNCTION:-flytedemo-delegator}" \
        --cli-binary-format raw-in-base64-out --payload "$DELEG_PAYLOAD" "$DELEG_OUT" 2>&1) \
        || fail "delegator Lambda invoke failed: $DELEG_META"
    grep -q '"ok": *true' "$DELEG_OUT" \
        || fail "delegator rejected the request: $(cat "$DELEG_OUT")"
    rm -f "$DELEG_OUT"
    echo "   delegated. waiting ~30s for propagation..."; sleep 30
elif [ -n "${DELEGATION_PROFILE:-}" ] && [ -n "${DELEGATION_ZONE_ID:-}" ]; then
    # Direct delegation: the operator running this also holds creds for the parent account
    # (a separate AWS profile). Same-operator testing only.
    step "Delegating $FLYTE_DOMAIN into the parent zone (profile: $DELEGATION_PROFILE)..."
    DELEG_RRS=$(echo "$ZONE_NS" | python3 -c 'import json,sys; print(json.dumps([{"Value":n} for n in json.load(sys.stdin)]))')
    DELEG_BATCH=$(printf '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"%s","Type":"NS","TTL":300,"ResourceRecords":%s}}]}' "$FLYTE_DOMAIN" "$DELEG_RRS")
    # env -u clears the target-account creds so --profile actually selects the parent
    # account (env creds otherwise take precedence over --profile).
    env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
        aws route53 change-resource-record-sets --profile "$DELEGATION_PROFILE" \
        --hosted-zone-id "$DELEGATION_ZONE_ID" --change-batch "$DELEG_BATCH" \
        --query 'ChangeInfo.Status' --output text --no-cli-pager \
        || fail "direct delegation failed (check DELEGATION_PROFILE / DELEGATION_ZONE_ID)."
    echo "   waiting ~30s for delegation to propagate..."; sleep 30
else
    echo "No delegation configured -- assuming $FLYTE_DOMAIN is already resolvable."
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
    --no-fail-on-empty-changeset \
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
    "KiroNonce=$(date +%s)"          # re-trigger the Kiro enable custom resource each deploy
)
[ -n "$LLAMA_KEY" ] && PARAMS+=("LlamaCloudApiKey=$LLAMA_KEY")
aws cloudformation deploy \
    --stack-name "$SANDBOX_STACK" \
    --template-file "$REPO_ROOT/provisioning/kiro-sandbox.yaml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides "${PARAMS[@]}"

# --- the handout ------------------------------------------------------------------------
sbout() { aws cloudformation describe-stacks --stack-name "$SANDBOX_STACK" \
            --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
ROLE_ARN=$(sbout KiroSandboxRoleArn)
UI_URL=$(sbout FlyteUiUrl)
LOGIN_EMAIL=$(sbout FlyteLoginEmail)
LOGIN_PASS=$(sbout FlytePassword)
KIRO_USER=$(sbout KiroUserId)
KIRO_STATUS=$(sbout KiroStatus)
KIRO_ERROR=$(sbout KiroError)
KIRO_DEBUG=$(sbout KiroDebug)
KIRO_PROFILE=$(sbout KiroProfileArn)
KIRO_PASS=$(sbout KiroPassword)
KIRO_START=$(sbout KiroStartUrl)
REGISTRY=$(dbout ProdImageRegistry)                       # <acct>.dkr.ecr.<region>..../<repo>
ECR_HOST="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
ALLOWLIST=".$(echo "$FLYTE_DOMAIN" | cut -d. -f2-), .amazoncognito.com"
MCP_ARGS="-y mcp-remote https://flyte-mcp.apps.demo.hosted.unionai.cloud/flyte-mcp/mcp"
cat <<EOF

================================================================================
  $FLYTE_DOMAIN is ready. Everything the attendee needs (see setup/):

  FLYTE CONSOLE  (the devbox UI -- where you verify executions)
    URL       : $UI_URL
    login     : $LOGIN_EMAIL
    password  : $LOGIN_PASS

  CONFIGURE THE CLI  (one config; run once on the devbox / in a Kiro task)
    flyte create config --endpoint $FLYTE_DOMAIN --registry $REGISTRY --project flytesnacks --domain development

  DOCKER LOGIN TO ECR  (before building/pushing images)
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_HOST

  KIRO WEB  (the agent)
    Enable status        : $KIRO_STATUS   (instance/profile/Web flag/user/subscription via API)
    Sign in              : https://app.kiro.dev  ->  "your organization"
    Start URL            : $KIRO_START
    username             : $LOGIN_EMAIL
    password             : ${KIRO_PASS:-<none -- reset in Identity Center console>}  (one-time; set a new one on first sign-in)
    Sandbox IAM Role ARN : $ROLE_ARN
      (paste at Settings > Agent > Sandbox > IAM Role)
    Network allow-list   : $ALLOWLIST
    MCP server (local)   : command 'npx', args '$MCP_ARGS'

  THEN, in a Kiro task:  Run bash scripts/bootstrap.sh
================================================================================
EOF

# Kiro enablement is best-effort (private/undocumented API) -- surface diagnostics instead of
# failing the deploy. If it didn't fully succeed, show the error + trace and where to dig.
if [ "$KIRO_STATUS" != "ok" ]; then
    cat <<EOF

  !! KIRO ENABLE: $KIRO_STATUS ${KIRO_ERROR:+-- $KIRO_ERROR}
     trace : $KIRO_DEBUG
     logs  : FN=\$(aws cloudformation describe-stack-resources --stack-name $SANDBOX_STACK \\
               --query "StackResources[?contains(LogicalResourceId,'KiroEnableFn')].PhysicalResourceId" \\
               --output text --region $REGION); aws logs tail "/aws/lambda/\$FN" --region $REGION
     retry : re-run this deploy (the Kiro calls are idempotent + retry transient errors).
             Kiro enable is fully automated -- no console step; a failure here is a real bug,
             so send the trace above.
EOF
fi
