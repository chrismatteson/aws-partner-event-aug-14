# Provisioning — the AWS side of Kiro setup

Internal. This is what turns Kiro setup from "type eight secrets" into "paste one role
ARN." Deploy it into each attendee account after the devbox stack.

## Two entrypoints (same result, pick per how AWS deploys)

Both stand an account up end to end — derive `s<hash>.flytedemo.app`, self-delegate its zone,
bring up the devbox, wire + enable Kiro. They differ only in *how* they're driven:

- **`deploy.sh` — imperative, proven.** One command per account (`bash provisioning/deploy.sh`).
  Does the orchestration in shell. This is the path that's been run end to end. Use it for
  manual/scripted runs.
- **`root.yaml` — pure CloudFormation, for Workshop Studio.** A single template AWS deploys
  into each account (no shell to run); the `deploy.sh` orchestration is expressed as three tiny
  custom resources (`Prep` = derive domain + AMI→SSM, `Delegate` = assume-role + guard,
  `Wire` = fetch the Cognito secret/domain + instance role) plus a native zone and the two
  nested stacks. Handout values are stack **Outputs**. One-time build: `bash provisioning/publish.sh
  <s3-bucket>` packages the nested templates to S3 and prints the `TemplatesBaseUrl` +
  deploy command. **Not yet run end to end** (built while locked out of AWS) — validate it on
  one account before the fleet; `deploy.sh` remains the fallback.

## What you can and can't automate

**Kiro Web has no `AWS::Kiro::*` CloudFormation resource** and no admin-push for the
per-user agent config. But its access *is* fully scriptable — **no console step**: the whole
"enable Kiro" (Identity Center instance + profile + managed app + user + subscription) is
five API calls the `EnableKiro` custom resource makes at deploy time (see the Kiro Web access
section below). What remains irreducibly manual is only the per-attendee UI bits and the
user's login password: **connect GitHub · two allow-list entries · one MCP server · one role
ARN · set the IdC user password (invitation email).** Verified against Kiro's docs, the
`amazon-q-developer-cli` source, a HAR capture of the Q Developer console, and community
tooling, Aug 2026.

**What you *can* provision** is the AWS scaffolding that makes that floor the whole job:

- an **IAM role** the sandbox assumes (short-lived creds, no static keys), and
- the per-attendee config in **SSM**, which `bootstrap.sh` reads at runtime using that role.

The net: the attendee types one value (the role ARN). No secrets on a card.

## DNS delegation: zero per-account action in the parent account

Each devbox needs a publicly-resolvable domain with a trusted wildcard cert
(`*.apps.<domain>`, for the Knative-hosted apps like Phoenix). The subdomain is derived
per account with **no manual assignment**: with no domain argument, `deploy.sh` builds
`s<8-hex-of-sha256(account-id)>.flytedemo.app` (e.g. `s0792067a.flytedemo.app`) — unique,
stable, and needing zero coordination, so the *same command* runs unchanged in every
account. deploy.sh creates that zone **in the attendee account**; it only becomes resolvable
once one `NS` record is delegated from the parent (`flytedemo.app`, which we own). The hard
requirement: **when AWS Workshop Studio stands up many accounts, each must delegate itself
with no action in our parent account, and nothing secret in the public repo.**

Two layers make that work:

- **One-time, private — `delegator-role.yaml`.** Deploy this stack **once** in the parent
  account. It creates a role attendee accounts assume (gated by an external-id) plus a
  guard Lambda. Workshop Studio SCPs block cross-org Function URL calls but **not**
  `sts:AssumeRole`, which is the one channel a locked-down account can use to reach in.

  ```bash
  aws cloudformation deploy --stack-name flytedemo-delegator \
    --template-file provisioning/delegator-role.yaml \
    --capabilities CAPABILITY_NAMED_IAM --region us-east-1 \
    --parameter-overrides ParentZoneId=<parent-zone-id> ParentDomain=flytedemo.app \
      LabelPattern='^student[0-9]{1,4}$' DelegationExternalId=<generate-a-secret>
  ```

- **Per-account, public — `deploy.sh`.** The public repo carries only mechanism. `deploy.sh`
  reads `DELEGATOR_ROLE_ARN` (an identifier, not a secret) and `DELEGATION_EXTERNAL_ID` (the
  secret, injected by your private Workshop Studio provisioning — never committed) from the
  environment. It assumes the role with the attendee account's **own** creds and calls the
  guard, which writes the single `NS` record. No parent-account credentials touch the deploy.

**What the guard allows — the bare minimum, nothing else.** The assumed role has *no* raw
Route 53 access; it can only invoke the guard Lambda, which enforces, in code:

- a **single label** under the parent (no apex, no multi-level names),
- matching **`LabelPattern`** (e.g. `^student[0-9]{1,4}$`),
- an **`NS` record only** — never MX/TXT/A/etc. on the parent,
- nameservers that are **AWS Route 53 (`awsdns`) hosts** — can't point a subdomain at
  attacker infrastructure,
- **first-writer-wins** — can't overwrite another attendee's existing delegation.

So even a leaked external-id can do nothing to `flytedemo.app` but create a `studentNN` NS
delegation to an AWS zone. (The child zone `studentNN.flytedemo.app` is then fully the
attendee's, inside their own account — that's what delegation *is*, and it can't affect the
parent or any other attendee.)

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

## Kiro Web access: Identity Center user + subscription (`kiro-setup.py`)

Kiro Web (app.kiro.dev) — the autonomous-agent surface where the attendee pastes the
sandbox role — is **IAM Identity Center only** (no Builder ID / personal login). The
console "enable Kiro" is, at the API level, **five calls**, and they're now **wired into
`kiro-sandbox.yaml`** as the `EnableKiro` custom resource, so `deploy.sh` sets Kiro up
end-to-end with **no console step**:

1. `sso-admin:CreateInstance` (public) → IAM Identity Center **account** instance (works —
   no org/management account needed; retry on the async SLR-cleanup conflict)
2. `AWSCodeWhispererService.CreateProfile` (**private**, signing name `codewhisperer`) → the
   Kiro control-plane profile (and, as a side effect, the `QDevProfile` managed application).
   The critical field: `identitySource.ssoIdentitySource.{instanceArn, **ssoRegion**}` — using
   `identityStoreId` here is what produced "Invalid identity center configuration". Also pass
   `referenceTrackerConfiguration.recommendationsWithReferences` + `activeFunctionalities`.
3. `iam:CreateServiceLinkedRole user-subscriptions.amazonaws.com` (public)
4. `identitystore:CreateUser` (public) → the attendee's Identity Center user
5. `AmazonQDeveloperService.CreateAssignment` (**private**, signing name `q`) → the Kiro
   subscription tier (retry: briefly "not authorized" right after CreateProfile; a re-run of
   an existing sub returns Conflict/"invalid state" = idempotent success)

Steps 2 and 5 are private, undocumented APIs (endpoint `codewhisperer.<region>.amazonaws.com`,
reverse-engineered from AWS's own `aws/amazon-q-developer-cli` **plus a HAR capture of the Q
Developer console** — which is where the `ssoRegion` field came from). **Unsupported; may
change.** Proven end-to-end from zero. `provisioning/kiro-setup.py` is the same logic as a
standalone CLI (useful for a central Identity Center or ad-hoc runs):

```bash
python provisioning/kiro-setup.py --email student05@flytedemo.app --tier pro
```

**Still manual: the Identity Center user's password.** `CreateUser` uses `PasswordMode=EMAIL`,
so the attendee gets in via an Identity Center invitation email (or your external IdP) — a
generic `workshop@…` mailbox won't receive it. That's the one piece the stack can't set
directly; for the real event, use attendees' real emails or wire a set-password path.

## What still isn't provisioned (the attendee/admin does these once)

| Step | Why it can't be a per-account CFN stack |
|---|---|
| The Identity Center user's app.kiro.dev password | `CreateUser` sends an invitation email; the stack can't set a password directly. Use real attendee emails, or an external IdP. |
| Connect GitHub + fork | Each user OAuths their own GitHub; no pre-attach. Fork needed for write access. |
| Network allow-list (2 entries) | UI-only, per user. But the two entries are the same for everyone — pre-print them. |
| MCP server (1) | UI-only, local-stdio only; `npx mcp-remote` bridge. No repo/admin path. |
| Paste the role ARN | Settings > Agent > Sandbox > IAM Role. The one per-attendee value. |

## The DNS assumption that makes the allow-list fixed

The network allow-list is UI-only and per attendee, so the only way to pre-print it is to
make its entries identical for everyone. That holds automatically: every devbox lives under
the shared parent `flytedemo.app` (each account self-delegates `s<hash>.flytedemo.app`, see
the DNS delegation section above), so the allow-list is always `.flytedemo.app,
.amazoncognito.com` — no per-attendee entry. (`.amazoncognito.com` already covers every
account's Cognito.)
