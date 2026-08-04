# Organizer runbook

Internal. Not for attendees.

Everything here is either a decision with a reason, a task with an owner, or a risk with
a test. Read the **red tests** section first — a couple of unknowns can invalidate the
architecture, and they're cheap to settle now and expensive to discover on August 14.

---

## The architecture, and why

Attendees never install anything, and type one value (a role ARN). Browser tabs only:

```
                        sandbox IAM role (assumed by q.amazonaws.com)
                                 │  short-lived creds
                                 ▼
   Kiro Web  ──── HTTPS + Cognito M2M ────▶  devbox (EC2, k3s)  ──▶  task pods
  (the agent,      (ExternalCommand auth)      in the attendee's         │
   no terminal,          ▲                        AWS account            │
   podman+shim)          │ config from SSM             ▲                 │
       │                 └──────── SSM ◀── provisioning │                 ▼
       └──── podman push ───▶  ECR ──── pull ──────────┴──▶   Bedrock (instance role)
                          (same account,                       LlamaCloud (key from SSM)
                           create-on-push)                     Phoenix (in-cluster app)

                                          Flyte UI ────▶ the attendee's
                                                          observation surface
```

**Decisions worth knowing the reasons for:**

**1. Devbox runs on EC2, not in Kiro's sandbox.** `flyte start devbox` hardcodes
`--privileged` Docker running k3s, with no opt-out. Kiro's sandbox has podman, not a
privileged Docker daemon — and *building* images (which podman does fine) is a very
different ask from *running a privileged k8s cluster*. The flyte-aws-marketplace devbox
makes it moot either way.

**2. Prod mode is mandatory.** Dev mode is IP-locked via `AllowedCidr`, and Kiro's
sandbox egress IP is unknown and dynamic — there's nothing to lock to. Prod mode also
gives us Cognito, which is the only headless auth path (below), and S3, which
[quietly saves the whole thing](#-red-1-the-code-bundle-upload-must-not-resolve-to-localhost).

**3. Auth is Cognito M2M, not PKCE.** PKCE opens a browser to complete the redirect.
There is no browser in the sandbox. `scripts/flyte-token.sh` does the client-credentials
grant and `.flyte/config.yaml` wires it in via `authType: ExternalCommand` — the flow the
devbox README documents for CI.

**4. Attendees build images, in the sandbox, pushed to their own ECR.** This is the
marketplace devbox's *intended* design — the stack already provisions ECR and auto-wires
it into Flyte at boot. Three moving parts make it work in Kiro Web:

- **`scripts/docker-shim.sh`** — Flyte's builder shells out to `docker buildx`; the
  sandbox has podman. The shim fakes the buildx subcommands the SDK probes (`version`,
  `ls`, `inspect`, `create`, `rm`) and translates `buildx build --push` into
  `podman build` + `podman push`. Installed by `bootstrap.sh`.
- **ECR login** — ⚠️ **the SDK never logs in to any registry.** I checked
  `docker_builder.py`: there is no login/auth code path at all; it assumes the daemon is
  already authenticated. `bootstrap.sh` does `aws ecr get-login-password | docker login`.
  Good for 12 hours, so a late-afternoon `401` means re-run bootstrap.
- **`image.registry`** in the config, set to `<acct>.dkr.ecr.<region>.amazonaws.com`.
  Verified in the SDK: `Image.uri` composes `f"{registry}/{name}:{tag}"`, and without
  `registry` set it falls back to `ghcr.io/flyteorg` (`_BASE_REGISTRY`), which nobody can
  push to. The `localhost:30000` fallback only triggers when the endpoint contains
  "localhost" — ours doesn't.

> ✅ **The ECR repo-name problem is solved by AWS, recently.** `Image.uri` is
> `{registry}/{name}:{tag}` with `name` defaulting to `flyte` — so a differently-named
> image would need a differently-named ECR repo, and ECR historically would not create
> one on push. [ECR create-on-push shipped 2025-12-19](https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-ecr-creating-repositories-on-push/).
> **It is not on by default** — each account needs a
> [repository creation template](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-creation-templates.html)
> with `appliedFor = CREATE_ON_PUSH`. With it, attendees can name images anything and
> pushes just work. **Without it, any image not named `flyte` fails to push.** Provisioning
> step, see the checklist.

**4b. The prebuilt image survives as a fallback, not the default.** `images/Dockerfile`
still builds an image with every dependency. `WORKSHOP_IMAGE` is *not* on the attendee
card — it's a lever facilitators pull if builds break on the day. The steering file tells
the agent to use it only when told to. Cheap insurance for a path with three new failure
modes (shim, ECR auth, build time) in Module 01 at 09:45 for 40 people at once.

> ⚠️ The `mlflow_server.py` example still can't be copied verbatim as an app template —
> it uses `Image.from_uv_script(__file__)`, which builds *the app's own image*. For
> off-the-shelf servers like Phoenix, pin the published image with `from_base` and set
> `command=`. Rule of thumb we teach: **build when the image is yours, pin when it's
> someone else's.**

**4c. Kiro setup is one pasted value, because the AWS side is provisioned.** You can't
CloudFormation Kiro itself (no resource type, no admin-push for agent config — verified).
But [`provisioning/kiro-sandbox.yaml`](provisioning/) bakes a **sandbox IAM role** and the
per-attendee config in **SSM**, so the attendee pastes only the role ARN and `bootstrap.sh`
fetches the rest. This collapsed the card from eight secrets to one. It leans on a
July-2026 Preview feature; **red test 6b** gates it, with the typed-secrets flow in git
history as the fallback. Kiro enablement itself — Identity Center instance + profile +
Pro subscription — is now **fully automated by the deploy** via API (no console step; see
provisioning/README.md). The irreducible manual floor: connect GitHub, two allow-list
entries, one MCP server, paste the ARN, and set the Identity Center user's password (the
one bit the deploy can't set — it sends an invitation email).

**4d. The whole workshop is one Kiro task.** Decided. The sandbox spins up once, bootstrap
runs once, `work/` persists in that sandbox all day (it stays gitignored — no need to
commit scratch). Simpler than task-per-module, and fine because the day is a few hours, not
eight. The cost: **the entire day rides on that one sandbox staying alive** — which makes
sandbox longevity (red test 9) load-bearing rather than nice-to-know. If a sandbox recycles
mid-session, that attendee re-runs `bootstrap.sh` (cheap now — no secrets to retype) and
loses only their uncommitted `work/`. Module 99 tells attendees to force-add anything worth
keeping before they close the tab.

**5. Phoenix runs as a Flyte app on each attendee's devbox.** Not Phoenix Cloud, not
Docker. **Empirically verified** on a real devbox: deployed, span sent from a task pod,
span read back. Apps are `flyte.app.AppEnvironment` (not `App`), backed by Knative, and
**enabled by default on the OSS devbox** (`internalApps.enabled: true`) — not Union-gated.
Task pods reach it over in-cluster DNS on **port 80**, bypassing the ALB, so Cognito is
irrelevant to OTLP export.

> **Correction to the "it's been done before" premise:** there is **no** prior art for
> Phoenix-as-an-app. Union v1's `PhoenixConfig` does the *opposite* — it points tasks at
> an externally-hosted `app.phoenix.arize.com`. There's no v2 port and no repo to copy.
> The nearest template is `flyte-sdk/examples/apps/tei/app.py` (off-the-shelf image via
> `command=`, bypassing the default `fserve` entrypoint).

**6. LLM access is Bedrock via the EC2 instance role. No API keys.** Attendee code uses
`AnthropicBedrockMantle` — a two-line diff from normal Claude usage — and credentials
resolve from IMDS. **Tracing needs zero changes**: `openinference-instrumentation-anthropic`
patches `anthropic.resources.messages.Messages`, which `Anthropic`, `AnthropicBedrock`,
and `AnthropicBedrockMantle` all share.

---

## 🔴 Red tests — settle these before anything else

Each is cheap. Each can invalidate a chunk of the design. Do them in this order.

### 🔴 1. The code-bundle upload must not resolve to `localhost`

**The single highest-risk unknown.** `flyte run` asks the cluster's data proxy for a
signed upload URL, then **PUTs the code tarball directly to whatever host that URL
names** — the transfer does not proxy through the API endpoint. If the devbox mints URLs
containing `localhost:300xx`, the sandbox resolves `localhost` to *itself*, and the
upload dies with `RuntimeSystemError("UploadFailed")` after `create_upload_location`
appears to succeed. **There is no endpoint-rewrite hook in the SDK.** No amount of image
or auth work avoids this.

**Why it should be fine:** Prod mode uses real S3, so signed URLs should carry
`*.s3.amazonaws.com` hostnames. Dev mode's in-cluster rustfs is where this would bite.

**Test:** from any machine that is *not* the devbox host, `flyte run` a trivial task
against a Prod-mode devbox over its DNS name. If the bundle uploads, this is settled
forever.

**If it fails:** we're on Dev mode, or S3 isn't wired. Fix the stack, not the workshop.

### 🔴 2. IMDS must be reachable from inside a task pod

**The crux of the no-API-keys design.** Bedrock credentials come from the EC2 instance
role via IMDS. IMDSv2's default `HttpPutResponseHopLimit` is **1**, and AWS's own docs say
that for containers "going to the container is considered an additional network hop" — so
the token response never arrives and credential resolution fails.

**Our topology is worse than the documented case.** The usual "set hop limit to 2" advice
assumes one Docker bridge. We have **k3s-in-Docker**: pod → flannel → k3s node container →
host. That's plausibly **3 hops**. This is **not documented anywhere** and is **untested**.

**Test — do this from inside a real task pod on a real devbox.** Not from the host, not
from a plain `docker run`; the whole question is the nesting.

```bash
aws ec2 modify-instance-metadata-options --instance-id i-xxxx \
  --http-tokens required --http-put-response-hop-limit 3 --http-endpoint enabled
```
Takes effect immediately, no restart. Then run a task that does
`boto3.client("sts").get_caller_identity()` and confirm it returns the instance role.
Find the hop limit that actually works, then bake it into the launch template /
CFN `MetadataOptions.HttpPutResponseHopLimit` for all 40 accounts.

Also needed on the instance role: **`bedrock-mantle:CreateInference`** (note: *not*
`bedrock:InvokeModel` — that's the legacy surface) plus
`aws-marketplace:Subscribe`/`Unsubscribe`/`ViewSubscriptions`. And `AWS_REGION=us-east-1`
in the task env — the client won't infer it.

**If it fails and can't be fixed:** put `ANTHROPIC_API_KEY` in SSM as
`/workshop/anthropic-api-key`, have `bootstrap.sh` export it, add `api.anthropic.com` to
the allow-list, and Module 11 changes by two lines (`AnthropicBedrockMantle()` →
`Anthropic()`). Know this before the day.

### 🔴 3. Bedrock quota in a freshly provisioned account must be non-zero

**The sleeper risk, and the only one with a slow fix.** Both Bedrock quota pages warn
"new AWS accounts might receive reduced quotas," and there are field reports of new
accounts showing an **applied quota of 0**. Our accounts are brand new by construction.
**A zero quota is indistinguishable from "no access" from the attendee's seat.**

Worse: Mantle quota increases **cannot be self-served** through Service Quotas. They need
an AWS Support case, and approval is normally gated on demonstrated usage we won't have.
**That's a multi-day path with four weeks on the clock.**

**Test this week:** check applied quota in one sample provisioned account. Then **pre-warm
every account with one throwaway invocation** — first invocation triggers a background
Marketplace auto-subscribe with a **~15-minute window** where calls intermittently return
`AccessDeniedException`. Nobody should meet that live.

**Good news, so we don't over-worry:** model access is **not** a blocker. It's been
default-on since Oct 2025, and the Anthropic first-time-use form doesn't apply to the
`bedrock-mantle` endpoint at all. That's the main reason we're on Mantle rather than the
legacy surface — it also moots the question of whether the 40 accounts are in our AWS
Organization or an AWS-controlled one.

### 🔴 4. Kiro Web must actually run `npx mcp-remote`

Kiro Web supports **local (stdio) MCP servers only** — remote MCP is documented as *not
available*. The Flyte MCP server is remote. `setup/README.md` bridges it with
`npx -y mcp-remote <url>`.

**Unverified:** that Kiro Web's sandbox has `npx`, allows it to fetch a package, and
keeps the bridge alive. The MCP docs say servers run via `uvx`/`npx` **outside** the
agent's tool sandbox, which is encouraging but not proof.

**Test:** configure it in a real Kiro Web account and run Setup Checkpoint B.

**If it fails:** the MCP-first premise is gone in Kiro Web. Fallbacks, in order: (a) the
`.kiro/steering/flyte-v2.md` file is already a deliberate hedge — expand it into a real
condensed API reference; (b) vendor the Flyte docs into the repo so the agent can grep
them; (c) reconsider Kiro IDE/CLI, which *does* support remote MCP.

> There's an internal contradiction in Kiro's own docs here — the Add-server UI reportedly
> offers a `HTTP or local` type field while the same page says remote isn't supported.
> Worth trying the direct URL first; if it works, drop the shim from the setup doc.

### 🔴 5. The devbox's k3s must pull from `ghcr.io`

Tasks pin `ghcr.io/unionai-oss/aws-workshop:...`. `--registry` cannot redirect a
fully-qualified URI — verified, there's no mirror/rewrite anywhere in the SDK. The URI
goes to k8s as-is.

**Should be fine** (containerd pulls public registries by default; `localhost:30000` is
an *additional* registry, not a replacement) but it's unverifiable from SDK source.

**Test:** run one task pinned to the image. Watch for `ImagePullBackOff`.

⚠️ **The image must be PUBLIC.** The SDK registers image-pull secrets but never emits
`imagePullSecrets` into a pod spec — the backend has to attach them. A private image is
an unfixable-on-the-day `ImagePullBackOff` for all 40 people.

### 🔴 5b. The whole build → push → pull loop, from the sandbox

**The newest and least-proven part of the design.** Kiro reportedly got building working
via podman + the shim; that's the report, not a verified end-to-end run against our stack.
Four things have to hold, and they fail in different places:

1. **The shim satisfies Flyte's builder.** `bootstrap.sh` asserts `docker buildx version`
   responds, which proves it's installed — **not** that a real build works. Flyte probes
   `buildx ls`/`inspect`/`create`; if it calls anything the shim doesn't case on, it exits
   1 with "unsupported buildx command", which is at least a loud failure.
2. **`podman push` reaches ECR** after `bootstrap.sh`'s login.
3. **ECR create-on-push fires** — needs the repository creation template (above).
   Without it, any image not named `flyte` fails.
4. **The devbox's k3s pulls the pushed image.** The stack auto-wires ECR, and the node's
   instance role should cover the pull — but confirm, because `ImagePullBackOff` at 09:45
   is the worst possible timing.

**Test:** from a real Kiro Web sandbox, run `bootstrap.sh` then `flyte run` a task using
`Image.from_debian_base().with_pip_packages("pandas")`. Watch it build, push, and run.
**Then time it** — if a cold build with apt packages takes more than ~5 minutes, Module 10
needs its image built during the break, not live.

**If it fails:** hand out `WORKSHOP_IMAGE` and pin. That fallback is why `images/Dockerfile`
still exists and why the steering file documents the escape hatch. Decide this *before* the
day, not at 09:50.

### 🟠 5c. Shim edge cases

I tightened the shim relative to the version Kiro generated. Worth knowing what changed and
what's still exposed:

- **Fixed:** `--provenance`/`--sbom` were only stripped in `=` form; the space form would
  have leaked a bare value into podman. Now both forms, plus `--attest`.
- **Fixed:** only the last `--tag` was pushed. Now all of them. Flyte passes one today, but
  silently pushing 1-of-N would be a miserable bug.
- **Fixed:** falls back to `$(command -v podman)` if podman isn't at `/usr/local/bin/podman`.
- **Still exposed:** forced `linux/amd64` (fine — devbox is amd64); `--load` dropped (fine
  — podman build already leaves the image in local storage, but if Flyte ever builds
  *without* `--push` and expects a loadable image, check this first).

### 🟠 6. Kiro seats

**Now self-provisioned by the deploy** — it assigns each attendee a Q Developer **Pro**
subscription via API (`CreateAssignment`, proven end-to-end from zero), so this is no longer
the procurement dependency it was. Still confirm two things: it runs in **`us-east-1`** (the
only preview region), and that self-subscribed Pro seats are fine on the billing/policy side
(~$20/mo/seat prorated — trivial for a one-day throwaway account, but know it's there).

### 🔴 6b. The sandbox IAM role → SSM path actually works

**The linchpin of the streamlined setup, and a three-week-old Preview feature.** The entire
"one value on the card" design assumes: a Kiro Web sandbox can assume the role we bake, and
with those creds `bootstrap.sh` can read `/workshop/*` from SSM. Both are plausible — the
trust principal (`q.amazonaws.com`), actions, and UI location are
[documented](https://kiro.dev/docs/web/sandbox/environment-configuration/) and the SSM read
is vanilla IAM — but the role feature shipped July 1 and neither has been run against our
template.

Two things could bite: (a) Kiro may **reject the role on save** if it validates a trust
policy shape we don't match — specifically we *omit* the `sts:SourceIdentity` value
condition its example includes; if the validator requires it, we can't pre-bake and fall
back to typed secrets; (b) the assumed-role creds must reach the **standard credential
chain** so `aws`/`boto3`/`podman` pick them up with no extra config — documented behavior,
unverified here.

**Test:** in a real Kiro Web sandbox, paste a provisioned role ARN, save (does it
validate?), start a task, run `aws sts get-caller-identity` and `aws ssm get-parameter
--name /workshop/flyte-domain`. Then the full `bootstrap.sh`.

**If it fails:** revert `setup/README.md` and `bootstrap.sh` to the typed-secrets flow
(it's in git history) — eight secrets on a card, but proven. Decide this **at T-3 weeks**,
because it changes the card, the provisioning, and the setup doc.

### 🟠 7. `ExternalCommand` auth against the ALB

`scripts/flyte-token.sh` requests scope `https://$FLYTE_DOMAIN/access`. The ALB's
`jwt-validation` rule checks for exactly that scope on `flyteidl2.*` calls. **Scope
strings must match the stack byte-for-byte.**

**Test:** `bash scripts/bootstrap.sh` end-to-end. It's written to isolate exactly this —
it mints a token first, *then* calls `flyte get config`, so a scope mismatch reports as
an auth error rather than a mystery.

### 🟠 8. Network allow-list semantics

Unverified: whether a custom allow-list **adds to** the "Common dependencies" tier or
**replaces** it. `setup/README.md` assumes additive (level = Common dependencies,
*plus* custom entries).

**Test:** set it as documented, then confirm both `pip install` (needs `pypi.org`, from
the tier) and the Cognito call (needs the custom entry) work in one task. **If it
replaces**, the setup doc needs the full list spelled out.

### 🔴 9. Sandbox longevity

**Load-bearing, because the whole workshop is one Kiro task (decision 4d).** The single
sandbox must survive the entire session — a few hours, across at least one break. Kiro Web
documents **no max task duration and no idle timeout** (only 90-day session data
retention), so this is an unverified property the whole day rides on.

**Test:** start a task, leave it idle through a break's worth of time, come back, run
something. Confirm the sandbox is still alive and the shim / ECR login / `.flyte/` state
survived.

**If sandboxes recycle mid-session:** an attendee re-runs `bootstrap.sh` (cheap now — it
fetches from SSM, no secrets to retype) and loses only uncommitted `work/`. Tell
facilitators this in advance so a recycle reads as a 60-second recovery, not a crisis. If
they recycle *often*, reconsider task-per-module — but that's a bigger change; verify
first.

### 🟠 10. The Phoenix app on *our* devbox, not a local one

The Phoenix-as-app verification was done on a **local** devbox. Two things could differ on
the ALB/Cognito EC2 build:

- **`internalApps.baseDomain`** is `localhost` on the local devbox. The **in-cluster path
  doesn't care** (it goes via `kourier-internal`), so span export should be unaffected —
  but the **public URL for viewing the Phoenix UI** does care, and I have not verified it
  on the ALB devbox. **Module 11 deliberately has Kiro fetch the URL rather than printing
  one as fact.** Confirm the real pattern during the dry run.
- **Project/domain/namespace naming** feeds the in-cluster DNS name
  (`phoenix-{project}-{domain}.{namespace}.svc.cluster.local`). Confirm ours matches
  `flytesnacks`/`development`/`flyte`.

Both are one command away: `kubectl get cm flyte-binary-config -n flyte`.

---

## Pre-event checklist

### T-3 weeks — the gating week
- [ ] **Red test 2: IMDS from inside a real task pod.** Find the working hop limit. Nothing
      about the no-keys design is real until this passes. **Do it first.**
- [ ] **Red test 3: check applied Bedrock quota** in a sample provisioned account. If it's
      0, open the AWS Support case **today** — it's the only item here with a multi-day fix.
- [ ] **Confirm Kiro seats with AWS** (red test 6). Pro+, us-east-1, one per attendee.
- [ ] **Red test 6b: the sandbox role → SSM path.** Paste a provisioned ARN into a real
      Kiro sandbox, confirm it validates on save, and that `bootstrap.sh` reads SSM with it.
      This is what the one-value card rests on — if it fails, fall back to typed secrets,
      and that decision has to be made now, not at T-1 week.
- [ ] Run red tests 1, 4, 5, **5b** against one throwaway Prod-mode devbox. **These gate
      everything.** 5b (build → push → pull) is the newest and least proven — and it now
      sits in Module 01, so if it's shaky the whole day is shaky. **Time a cold build.**
- [ ] **Red test 9: sandbox longevity.** The whole day is one Kiro task, so the sandbox
      must survive the session across a break. Leave one idle, come back, confirm it lives
      and its state survived. If it recycles, brief facilitators on the re-run recovery.
- [ ] Ask AWS whether promo credits cover Bedrock 3P model usage.
- [ ] **Deploy the delegator role once** (`provisioning/delegator-role.yaml`) in the
      `flytedemo.app` account and set the external-id secret. After that, every account's
      subdomain auto-derives (`s<hash>.flytedemo.app`) and self-delegates — no per-account
      DNS, no zone ID to plumb, no action in the parent account per deploy.

### T-2 weeks
- [ ] Build and push the workshop image, **public**, immutable tag:
      ```bash
      docker build -f images/Dockerfile -t ghcr.io/unionai-oss/aws-workshop:2026-08-14 .
      docker push ghcr.io/unionai-oss/aws-workshop:2026-08-14
      ```
      The Dockerfile self-checks `a0` and the imports at build time — a green build means
      the entrypoint and every module dependency resolve.
- [ ] **Do a full dry run as an attendee.** Fresh Kiro account, fresh AWS account, only
      the card. Walk `setup/` → Module 03 without touching a terminal. This is the single
      most valuable hour available; everything below is guesswork without it.
- [ ] Verify every module's prompts actually produce working code **with the MCP
      connected**. The modules deliberately don't pin API signatures — that's a hedge
      against drift, but it means the MCP has to be good enough.
- [ ] **Deploy the Phoenix app on the ALB devbox** (red test 10) and confirm the in-cluster
      DNS name and the public UI URL. Module 11 has Kiro fetch the URL rather than
      asserting one — verify the real pattern here.
- [ ] **Assert on a real Phoenix span** from an `AnthropicBedrockMantle` call — don't
      eyeball the UI. Confirm model name and token counts actually populate. Wrong
      instrumentor, missing package, and unflushed spans all fail *silently and
      identically*; the only way to know is to assert.

### T-1 week
- [ ] Provision 40 AWS accounts, each with a devbox Prod stack + DNS.
- [ ] **Create an ECR repository creation template** in each account with
      `appliedFor = CREATE_ON_PUSH`. Without it, attendees can only push images named
      `flyte`, and any agent that picks a different name fails confusingly.
- [ ] **Run `bash provisioning/deploy.sh` in each account** — one command, no args. It
      derives the subdomain, self-delegates the zone, deploys the devbox + the Kiro
      provisioning stack, and enables Kiro end-to-end via API (Identity Center instance +
      profile + user + Pro subscription). See [provisioning/README.md](provisioning/README.md).
      One command × 40, scriptable.
- [ ] **Capture each account's role ARN** from the deploy output (`KiroSandboxRoleArn`).
      That's the whole card — nothing secret transcribed by hand.
- [ ] **Set each Identity Center user's password.** `CreateUser` sends an invitation email,
      so use attendees' real emails (they get the invite) or an external IdP — the one Kiro
      bit the deploy can't set. GitHub is connected per-attendee in the Kiro UI.
- [ ] **Bake the IMDS hop limit** (whatever red test 2 landed on) into the launch template
      / CFN `MetadataOptions.HttpPutResponseHopLimit`.
- [ ] **Add Bedrock permissions to the instance role**: `bedrock-mantle:CreateInference`
      (**not** `bedrock:InvokeModel` — wrong surface) plus `aws-marketplace:Subscribe`,
      `Unsubscribe`, `ViewSubscriptions`.
- [ ] **Pre-warm Bedrock in every account** with one throwaway invocation. First call
      triggers a background Marketplace auto-subscribe with a ~15-minute window of
      intermittent `AccessDeniedException`. Nobody should meet that live.
- [ ] Confirm `AWS_REGION=us-east-1` reaches task pods.
- [ ] Set `AutoStop=No`, or raise `IdleThresholdMinutes` well past a lunch break. **The
      2-minute wake is fine once and infuriating four times.** Consider a pre-warm.
- [ ] Print the **handout**: sign-in identity + the two fixed allow-list domains + this
      account's one role ARN.
- [ ] Pre-create Cognito users if attendees need Flyte UI browser login.
- [ ] Confirm LlamaCloud keys: own key per attendee (own org ⇒ own 20 RPM ⇒ no
      contention). Do **not** share one key across the room; you'd serialize 40 people
      behind one rate limit.

### Day of
- [ ] Pre-warm every devbox in the morning. Nobody's first experience should be a
      2-minute wait.
- [ ] Facilitators: know the setup failure modes cold — the sandbox role not saved / not
      picked up (needs a fresh task), the two allow-list domains missing, the MCP server
      not added (Checkpoint B), and a sleeping devbox (2-min wake). Nearly every support
      question is one of these.
- [ ] Check <https://llamaindex.statuspage.io/> before Module 10.

---

## The attendee card

**One value.**

```
  KiroSandboxRoleArn   arn:aws:iam::<account>:role/kiro-workshop-<account>
```

Plus the two things that are the same for everyone and go on the printed handout, not a
per-attendee card: the Kiro sign-in identity, and the allow-list domains
(`.flytedemo.app, .amazoncognito.com`).

Everything else the sandbox reads for itself. The role (paste once, Settings → Agent →
Sandbox → IAM Role) gives it AWS creds; `bootstrap.sh` uses those to pull
`FLYTE_DOMAIN`, the Cognito details, and the LlamaCloud key from SSM. No secrets typed,
no keys to transcribe, no eight-value card to get wrong at 09:15.

**Not on the card, deliberately:**
- **No Claude key** — Bedrock resolves credentials from the instance role. **If red test 2
  (IMDS) fails**, put `ANTHROPIC_API_KEY` in SSM as a fallback, restore `api.anthropic.com`
  to the allow-list, and Module 11 swaps `AnthropicBedrockMantle(...)` for `Anthropic()`.
- **No AWS keys** — the sandbox IAM role replaced them. Short-lived, no static keys in a
  prompt-injectable agent.
- **No `WORKSHOP_IMAGE`** — the prebuilt-image fallback. Put it in SSM and point the
  steering at it only if builds break.

### How the one value is produced

The whole per-account provisioning — the role, the SSM params — lives in
[`provisioning/`](provisioning/) and its [README](provisioning/README.md) has the deploy
script. In short: the devbox stack already creates the Cognito M2M client and knows the
Flyte domain; the provisioning template turns those (plus the client secret, fetched via
`describe-user-pool-client`, and the Llama key) into SSM parameters and emits one role
ARN. Script it across 40 accounts; each emits its ARN.

**Why M2M, still:** a Cognito access token lives ~1 hour and would strand everyone after
the first session. `scripts/flyte-token.sh` mints a fresh token per CLI call from the
client credentials it reads out of `.flyte/workshop.env` (which bootstrap wrote from SSM),
so nothing expires mid-day.

### The security trade in one place

The role is assumable only by Kiro's service principal (`q.amazonaws.com`) and grants only
**SSM read on `/workshop/*` + ECR push** in a throwaway account. Kiro's reference trust
policy additionally pins the session to a specific Kiro user id; we omit that because
attendees have no id until they log in, so the role must be pre-bakeable. Consequence: any
Kiro user who learned an ARN could assume it — into an account that holds only a throwaway
devbox and is deleted after the event. The hardening (pin `sts:SourceIdentity` per
attendee) is documented in the template comment; it's not worth the per-attendee friction
here. **Revoke/delete everything after the event regardless.**

---

## Cost

| Item | Per attendee | × 40 |
|---|---|---|
| EC2 `m6i.2xlarge` @ $0.384/hr × ~8h | ~$3.10 | ~$125 |
| ALB (~$20/mo, prorated) | ~$0.70 | ~$28 |
| Aurora (scales to zero) | ~$0.10 | ~$4 |
| EBS + EIP | ~$0.50 | ~$20 |
| **AWS total (one day)** | **~$4.40** | **~$180** |
| LlamaCloud | free tier | $0 |
| Phoenix | self-hosted as a Flyte app | $0 |
| Bedrock (Claude Sonnet 5) | usage, ~$1–3 | ~$40–120 |
| Kiro Pro seats | $20/mo | **AWS to confirm** |

Bedrock matches first-party Claude pricing, and **Aug 14 falls inside the Sonnet 5
introductory window** ($2/$10 per 1M in/out vs the usual $3/$15). Use **global** rather
than regional endpoints — regional carries a +10% premium for data residency we don't
need. Prompt caching works on Bedrock and is worth wiring into a shared system prompt if
we care.

⚠️ **Do not assume AWS promotional credits cover Bedrock.** Third-party models transact
via AWS Marketplace, and Marketplace charges are commonly excluded from promo credits. I
couldn't find documentation settling this for Bedrock 3P usage specifically. **Ask the AWS
contact** — the amount is small either way, but "small surprise bill in 40 accounts" is a
bad look.

Cheap, as long as the accounts are actually torn down. **Set a teardown date.** The S3
bucket, EBS volume, and Aurora cluster are `Retain`/`Snapshot` on stack delete — deleting
the stack does *not* stop those charges. Delete the accounts.

---

## Open decisions

**Where Phoenix runs — decided: as a Flyte app on each attendee's devbox.** Verified
working end to end (deployed, span sent from a pod, span read back). It's the better
story — their cluster, their infra, one `flyte deploy`, no signup, no span quota — and it
lets Module 11 reuse the `flyte deploy` verb from Module 03 to ship a whole web service.
Phoenix Cloud is demoted to an aside.

The residual risk is the scale-to-zero footgun (`Scaling` defaults to `replicas=(0,1)`,
storage is ephemeral, so an idle Phoenix silently loses every trace). Module 11 pins
`replicas=(1,1)` and explains why. Confirm it holds across a lunch break during the dry run.

**The three partner stubs were cut** (Protopia, CloudZero, Portal26) — none had a
self-serve path an attendee could use in the time available. If any becomes a real track
later, **CloudZero is the one to build first**: its telemetry/AnyCost API contract is
public and precise, its `cloudzero-agent` is Apache-2.0 and reads pod labels, and Flyte
pods already carry `project`/`domain`/`workflow`/`execution-id` — a genuine integration
someone could ship, not a demo. Portal26's token-budget idea survives as a pure-Flyte
build-your-own suggestion in [Module 99](modules/99-now-you-drive.md).

**Repo discrepancy to check.** flyte-aws-marketplace's root README describes
`devbox/cloudformation/root.yaml` nesting `common/{data,auth}`, while `devbox/README.md`
describes a single self-contained `cloudformation/flyte-devbox.yaml`. The tree matches
the root README. `devbox/README.md` looks stale — worth fixing there, since our deploy
instructions reference it.

---

## Known sharp edges

**`org` auto-injection.** `flyte create config` derives `org` from any hostname with 3+
parts — `s0792067a.flytedemo.app` would silently write `org: s0792067a` into the
config, which the devbox won't know. **`scripts/bootstrap.sh` sidesteps this by writing
the YAML directly and omitting `org`.** If anyone "helpfully" switches it to
`flyte create config`, this comes back.

**`--insecure` disables auth, not just TLS.** Per the SDK's own comment. Irrelevant to us
(we're HTTPS + Cognito) but worth knowing: a raw devbox on public DNS with `--insecure`
is an unauthenticated k8s-backed cluster with arbitrary code execution and IMDS access to
the account. Never ship that.

**Devbox is 8 vCPU / 32 GB, total.** Module 02's 200-way fan-out is bounded by that. It's
a feature — attendees see queuing and concurrency limits for real — but if a task asks
for more memory than the box has, it sits in `Pending` forever. Module 03 warns about it.

**`pandas` 3.x and `plotly` 6.x are pinned in the image** and are majors ahead of what
most training data knows. If Kiro writes pandas 2 idioms in Module 03, that's the cause.

**Three ways Module 11 fails silently, producing zero spans and no error.** Facilitators
should know all three cold, because they're indistinguishable from the attendee's seat:
1. **Wrong instrumentor.** `openinference-instrumentation-bedrock` patches boto3's
   `bedrock-runtime` and does nothing for `AnthropicBedrockMantle`. It's deliberately
   *not* in the image so nobody reaches for it — but an agent may try to install it.
2. **Unflushed spans.** `BatchSpanProcessor` drops everything if the process exits first,
   and Flyte tasks are short-lived by design. Module 11 uses `batch=False` for this reason.
3. **Phoenix scaled to zero.** `Scaling` defaults to `replicas=(0,1)` with ephemeral
   storage — an idle Phoenix takes every trace with it. Module 11 pins `(1,1)`.

**The Phoenix image is distroless — no `/bin/sh`.** `command=["/bin/sh","-c",...]`
CrashLoops. The real entrypoint is `/usr/bin/python3.13 -m phoenix.server.main serve`.
It's exactly what an agent would get wrong.

**Knative routes one port.** Phoenix's OTLP-gRPC on 4317 is unreachable as an app; OTLP-
HTTP on 6006 is verified sufficient. Also: the image exposes 9090, which is Knative-
reserved — harmless (Phoenix's Prometheus is off by default), just never set `port=9090`.

**Everything on the public internet about Flyte is v1.** `@workflow`, `flytekit`,
`pyflyte`, `map_task` — the tell that the MCP isn't connected. Both the setup doc and the
steering file call this out because it's the failure that looks like success.
