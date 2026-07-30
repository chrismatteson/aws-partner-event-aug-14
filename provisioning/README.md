# Provisioning — the AWS side of Kiro setup

Internal. This is what turns Kiro setup from "type eight secrets" into "paste one role
ARN." Deploy it into each attendee account after the devbox stack.

## What you can and can't automate

**You cannot provision Kiro Web itself.** There is no `AWS::Kiro::*` CloudFormation
resource, no provisioning API, no Terraform provider, and no admin-push for agent config.
Enabling Kiro Web is an AWS Identity Center console toggle ("Autonomous agents" under
Kiro Settings), and each attendee connects their own GitHub and configures their own
sandbox by hand. That floor is irreducible: **connect GitHub · two allow-list entries ·
one MCP server · one role ARN.** Verified against Kiro's docs and changelog, July 2026.

**What you *can* provision** is the AWS scaffolding that makes that floor the whole job:

- an **IAM role** the sandbox assumes (short-lived creds, no static keys), and
- the per-attendee config in **SSM**, which `bootstrap.sh` reads at runtime using that role.

The net: the attendee types one value (the role ARN). No secrets on a card.

## Deploy, per account

**One `aws cloudformation deploy`.** `kiro-sandbox.yaml` is self-contained — it creates
the SSM config, the sandbox role, ECR create-on-push, and the Bedrock policy on the devbox
instance role, and outputs the role ARN. No imperative follow-up steps.

The inputs are the devbox stack's outputs plus the client secret and (optionally) the
LlamaCloud key. Gather them, then deploy:

```bash
DEVBOX_STACK=flyte-devbox-workshop     # the devbox stack in this account
REGION=us-east-1

Q() { aws cloudformation describe-stacks --stack-name "$DEVBOX_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

FLYTE_DOMAIN=$(Q FlyteCliEndpointProd)
POOL_ID=$(Q CognitoUserPoolId)
CLIENT_ID=$(Q CognitoM2MClientId)
CLIENT_SECRET=$(aws cognito-idp describe-user-pool-client --region "$REGION" \
  --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" \
  --query 'UserPoolClient.ClientSecret' --output text)

# Cognito hosted-UI domain (derive the prefix from the pool, or read it once).
COGNITO_DOMAIN="https://<prefix>.auth.${REGION}.amazoncognito.com"

# The EC2 instance role the devbox runs as — Bedrock perms attach to it.
INSTANCE_ROLE=$(aws cloudformation describe-stack-resources --stack-name "$DEVBOX_STACK" \
  --region "$REGION" --query "StackResources[?ResourceType=='AWS::CloudFormation::Stack' \
  && contains(LogicalResourceId,'Compute')].PhysicalResourceId" --output text)
INSTANCE_ROLE_NAME=$(aws cloudformation describe-stack-resources --stack-name "$INSTANCE_ROLE" \
  --region "$REGION" --query "StackResources[?LogicalResourceId=='InstanceRole'].PhysicalResourceId" \
  --output text)

LLAMA_KEY="llx-..."                    # this attendee's key, or "" to add later

aws cloudformation deploy \
  --stack-name kiro-sandbox \
  --template-file provisioning/kiro-sandbox.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --parameter-overrides \
      FlyteDomain="$FLYTE_DOMAIN" \
      CognitoDomain="$COGNITO_DOMAIN" \
      CognitoClientId="$CLIENT_ID" \
      CognitoClientSecret="$CLIENT_SECRET" \
      LlamaCloudApiKey="$LLAMA_KEY" \
      DevboxInstanceRoleName="$INSTANCE_ROLE_NAME"

# The one value that goes to the attendee:
aws cloudformation describe-stacks --stack-name kiro-sandbox --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='KiroSandboxRoleArn'].OutputValue" --output text
```

That final ARN is the attendee's whole card. Script it across all 40 accounts, one ARN
each.

> **Secrets are stored as SSM `String`, not `SecureString`**, because CloudFormation can't
> create a SecureString without a custom resource — and the goal here is one pure-CFN
> deploy. They're passed as `NoEcho` parameters and readable only by the sandbox role, in
> a throwaway account deleted after the event. For a durable deployment, make those two
> SecureString (custom resource or out-of-band) instead.

## What the role can do

Deliberately small: **read `/workshop/*` in SSM, push images to this account's ECR, and
`sts:GetCallerIdentity`.** Nothing else. It's assumable only by Kiro's service principal
(`q.amazonaws.com`).

The one loosened bolt: Kiro's reference trust policy pins the session to a specific Kiro
user id, which we can't know before attendees log in, so we omit that condition. Any Kiro
user who learned this ARN could assume it — but into an account that only holds a
throwaway devbox and gets deleted after the event. See the comment in the template for
how to pin it if you ever reuse this outside a workshop.

## What still isn't provisioned (the attendee does these once)

| Step | Why it can't be automated |
|---|---|
| Enable Kiro Web (admin) | Identity Center console toggle; no CFN, no API. One-time, org-wide. |
| Connect GitHub + fork | Each user OAuths their own GitHub; no pre-attach. Fork needed for write access. |
| Network allow-list (2 entries) | UI-only, per user. But the two entries are the same for everyone — pre-print them. |
| MCP server (1) | UI-only, local-stdio only; `npx mcp-remote` bridge. No repo/admin path. |
| Paste the role ARN | Settings > Agent > Sandbox > IAM Role. The one per-attendee value. |

## The DNS assumption that makes the allow-list fixed

The network allow-list is UI-only and per attendee, so the only way to pre-print it is to
make its entries identical for everyone. That happens if every devbox lives under one
shared zone — `studentNN.workshop.union.ai` — so the allow-list is always
`.workshop.union.ai, .amazoncognito.com`. Provision the devboxes under a shared Route 53
zone and the per-attendee allow-list entry disappears. (`.amazoncognito.com` already
covers every account's Cognito.)
