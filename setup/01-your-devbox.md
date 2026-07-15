# Meet your devbox

Optional reading. Useful if you like knowing what's actually underneath you — and if
you're wondering whether you could run this at work on Monday. (You can; it's one
CloudFormation deploy.)

## What's running in your AWS account

One EC2 instance — an `m6i.2xlarge`, 8 vCPU and 32 GB — running **k3s in Docker** with a
complete Flyte control plane inside it. It's a real Kubernetes cluster and a real Flyte
backend. Just small, and yours.

Around it:

| Piece | What it does |
|---|---|
| **ALB + ACM + Route 53** | HTTPS at your domain |
| **Cognito** | Authenticates you and Kiro |
| **S3** | Object store — your code bundles, inputs, outputs live here |
| **Aurora Serverless v2** | Flyte's metadata, scale-to-zero when idle |
| **ECR** | A registry, if you ever build images |

Your tasks run as **real pods on real Kubernetes**. When Module 02 fans out across 200
inputs, that's 200 pods being scheduled on that box, gated by 8 vCPU. Nothing is
simulated. The only thing separating this from a 500-node cluster is the node count.

## Why it keeps falling asleep

An idle agent watches for executions. Thirty minutes with none, and it stops the EC2 and
lets Aurora pause. An idle devbox costs a few dollars a month instead of ~$280.

The next request wakes it: it hits a Lambda, which authenticates you, starts the
instance (~2 min — the devbox image is already in the Docker volume, so there's no
re-pull), and flips traffic back. **This is why your first run of the day, and your first
run after lunch, take two minutes.** It's not broken. It's the feature that makes leaving
one of these running affordable.

## How Kiro authenticates

This is the one genuinely unusual thing about today's setup, and it's worth understanding
because it's *why* setup had those Cognito secrets in it.

A human on a laptop authenticates with **PKCE**: the CLI opens a browser, you log into
Cognito, done. Kiro's sandbox has no browser and no way to open one, so PKCE is
impossible.

Instead we use Cognito's **machine-to-machine client-credentials grant** — the same flow
CI systems use. `scripts/flyte-token.sh` exchanges a client ID and secret for a bearer
token, and `.flyte/config.yaml` tells the Flyte CLI to shell out to that script whenever
it needs one (`authType: ExternalCommand`). Every call gets a fresh token; nothing is
cached to disk.

If auth ever looks broken, run `bash scripts/flyte-token.sh` and read the error. It's
written to tell you which part failed.

## Where authorization stops

Cognito proves **who you are**. It does not do per-user authorization — any authenticated
principal has full control-plane access to this devbox. That's fine for a one-day
workshop where the box is yours and gets destroyed afterward. It is *not* a model for a
shared team cluster; that's where per-user RBAC starts to matter, and it's one of the
lines between the OSS devbox and Union's managed control plane.

Worth knowing what you're getting rather than finding out later.

## The boundary

This stack is deliberately **one box**: simple, cheap, auto-stopping. That's the whole
design goal. When you outgrow it — multi-node, HA, real concurrent load — that's the
line, and you move to **EKS + the Flyte Helm chart**, or a managed control plane. The
same repo ships an EKS product for exactly that.

Take it home: **[unionai-oss/flyte-aws-marketplace](https://github.com/unionai-oss/flyte-aws-marketplace)**
