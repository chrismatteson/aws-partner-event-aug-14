# Organizer runbook

Internal. Not for attendees.

## What this is

40 attendees, each with their own throwaway AWS account containing a **Flyte devbox**
(EC2 + k3s). They drive it from **Kiro Web** — a browser coding agent — with no laptop
setup and no repo to clone. The only things they touch are browser tabs.

```
   Kiro Web  ──── HTTPS + Cognito M2M ────▶  devbox (EC2, k3s)  ──▶  task pods
  (agent, no terminal)   (token from steering)   in their account        │
       │  sandbox IAM role (assumed by q.amazonaws.com) → creds          ▼
       └──── docker push ─▶ ECR ─▶ k3s pulls          Bedrock (EC2 instance role, no keys)
                                                       Flyte UI ─▶ their observation surface
```

**Key facts:**
- **Devbox runs on EC2, not in Kiro's sandbox** (`flyte start devbox` needs privileged
  Docker; the marketplace devbox moots it). Prod mode is mandatory — it gives Cognito
  (the only headless auth path) and real S3.
- **Auth is Cognito machine-to-machine, not PKCE** (no browser in the sandbox). The
  steering file writes `~/.flyte/config.yaml` with `authType: ExternalCommand` and a
  token script that does the client-credentials grant.
- **Kiro's sandbox has real Docker** — attendees build images in-sandbox and push to
  their own ECR.
- **LLM access is AWS Bedrock via the EC2 instance role — no API keys.** Attendee code uses
  `AnthropicBedrockMantle`; creds resolve from IMDS.

## How each account is provisioned

Everything per-account lives in [`provisioning/`](provisioning/); the deploy tooling and
docs are in [`operator/`](operator/README.md).

1. **Once, ever:** deploy the delegator role (`operator/delegator-role.yaml`) in the
   `flytedemo.app` account and set the external-id secret. After that every account's
   subdomain auto-derives (`s<hash>.flytedemo.app`) and self-delegates — no per-account DNS.
2. **Per account:** point AWS Workshop Studio at `root.yaml` (pure CloudFormation, no shell).
   It deploys the devbox + Kiro provisioning stack, writes per-attendee config to SSM, mints
   the sandbox IAM role, and **enables Kiro end-to-end via API**:
   Identity Center instance + profile + user + Pro subscription, **Kiro Cloud toggle on**, and
   **MFA disabled**. No console step. (Kiro's control-plane APIs are undocumented and have
   moved before — see `operator/README.md` and the private-API notes if enablement breaks.)
3. **Capture the CloudFormation Outputs** — that's the attendee handout (below).

## The attendee handout

Straight from the stack Outputs, in setup order:

```
KiroLoginUrl · KiroStartUrl · KiroRegion · KiroLoginEmail · KiroPassword · KiroSandboxRoleArn
FlyteUiUrl · FlyteLoginEmail · FlytePassword
```

No secrets typed by hand — the sandbox reads its Flyte domain, Cognito details, and any
keys from SSM using the role. Everything the attendee does is in [README.md](README.md#setup):
sign in to Kiro → allow all outbound → paste the MCP server → paste the role ARN → paste the
[steering file](.kiro/steering/workshop.md) → "connect to my devbox" → open the Flyte UI tab.

**Security trade:** the role is assumable only by `q.amazonaws.com` and grants only SSM-read
on `/workshop/*` + ECR push, in an account that's deleted after the event. We omit Kiro's
optional `sts:SourceIdentity` pin (attendees have no id until they log in, so the role must be
pre-bakeable). **Delete the accounts after the event regardless.**

## Verify before the day

These are the things that have actually bitten; settle them on one throwaway account first.

- [ ] **IMDS reaches task pods.** Bedrock creds come from the instance role via IMDS, and
      k3s-in-Docker adds hops. Set `MetadataOptions.HttpPutResponseHopLimit` high enough
      (test from *inside a task pod*: run `boto3.client("sts").get_caller_identity()`), then
      bake it into the launch template for all 40. Instance role also needs
      `bedrock-mantle:CreateInference` (**not** `bedrock:InvokeModel`) +
      `aws-marketplace:Subscribe/Unsubscribe/ViewSubscriptions`, and `AWS_REGION=us-east-1`
      in the task env.
- [ ] **Bedrock quota is non-zero** in a sample account (new accounts can show 0; a fix is a
      multi-day Support case). **Pre-warm every account** with one throwaway invocation — the
      first call triggers a ~15-min window of intermittent `AccessDeniedException`.
- [ ] **ECR create-on-push template** (`appliedFor = CREATE_ON_PUSH`) in each account —
      without it, only images named `flyte` can be pushed.
- [ ] **Build → push → pull works from a real Kiro sandbox.** Run "connect to my devbox" then
      `flyte run` a task using `Image.from_debian_base().with_pip_packages("pandas")`. Time a
      cold build. The workshop image (`images/Dockerfile`, pushed **public**) stays as a
      fallback: set `WORKSHOP_IMAGE` in SSM and point the steering at it only if builds break.
- [ ] **The pinned task image is PUBLIC** (private → unfixable `ImagePullBackOff` for everyone).
- [ ] **Sandbox longevity.** The whole day is one Kiro task; leave one idle across a break and
      confirm it (and `~/.flyte/` state) survives. If it recycles, an attendee just re-runs
      "connect to my devbox" — brief facilitators so it reads as a 60-second recovery.
- [ ] **Auth scope matches the stack.** The token requests `https://$FLYTE_DOMAIN/access`; the
      ALB checks that exact scope. "connect to my devbox" mints a token before calling Flyte,
      so a mismatch surfaces as a clear auth error.
- [ ] **Set `AutoStop=No`** (or a long idle threshold) and pre-warm every devbox the morning
      of — the 2-minute wake is fine once, infuriating four times.

**Modules 10 (LlamaIndex) and 11 (Arize Phoenix) are currently marked unavailable** in the
attendee materials while their data/setup is reworked. If you re-enable them, LlamaCloud needs
one key per attendee in SSM (own org ⇒ own rate limit), and Phoenix runs as a Flyte app on the
devbox — re-verify the in-cluster DNS name and public URL on the ALB build first.

## Day-of failure modes (facilitators know these cold)

Nearly every support question is one of:
- Sandbox role not saved / not picked up → needs a **fresh task**.
- Outbound internet not allowed, or the MCP server not pasted (Checkpoint B fails).
- Steering file not pasted → Kiro won't know how to connect.
- Sleeping devbox → first request takes ~2 min; wait and retry.

## Cost

| Item | Per attendee | × 40 |
|---|---|---|
| EC2 `m6i.2xlarge` ~8h | ~$3.10 | ~$125 |
| ALB + Aurora + EBS/EIP | ~$1.30 | ~$52 |
| **AWS total (one day)** | **~$4.40** | **~$180** |
| Bedrock (Claude Sonnet 5, usage) | ~$1–3 | ~$40–120 |
| Kiro Pro seats | ~$20/mo prorated | AWS to confirm |

Bedrock matches first-party Claude pricing; use **global** endpoints (regional is +10%).
⚠️ **Don't assume AWS promo credits cover Bedrock** — 3P models transact via Marketplace,
commonly excluded from promo credits. Ask the AWS contact. **Set a teardown date:** S3, EBS,
and Aurora are `Retain`/`Snapshot` on stack delete — deleting the stack doesn't stop those
charges. Delete the accounts.

## Known sharp edges

- **Everything online about Flyte is v1** (`@workflow`, `flytekit`, `pyflyte`, `map_task`) —
  the tell that the MCP isn't connected. The steering file calls this out hard.
- **Devbox is 8 vCPU / 32 GB total.** Module 02's 200-way fan-out is bounded by that (a
  feature — real queuing) but a task asking for more memory than the box has sits `Pending`
  forever.
- **`pandas` 3.x / `plotly` 6.x** are pinned and are majors ahead of most training data — if
  Kiro writes pandas 2 idioms, that's why.
- **Don't switch the auth to `flyte create config`** — it auto-injects `org` from the 3-part
  hostname, writing a bad `org:` the devbox won't know. The steering writes the YAML directly
  and omits `org`.
