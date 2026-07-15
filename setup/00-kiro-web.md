# Setup — wire up Kiro Web

You should have a **card** from your facilitator with eight values on it. Keep it handy;
you'll paste from it in step 3.

> **Why there's manual clicking here.** Kiro Web reads *some* of its configuration from
> this repo (the steering files in `.kiro/steering/` — those are already done for you).
> But secrets, network access, and MCP servers are per-user settings that live in your
> Kiro account, not in a repo. Nobody can pre-bake them for you. This is the one part
> of the day that isn't automated. It's ~20 minutes, once.

---

## 1. Sign in and connect the repo

1. Go to **[app.kiro.dev](https://app.kiro.dev)** and sign in with the identity your
   facilitator gave you.
2. Connect your **GitHub** account when prompted.
3. **Fork this repo** to your own GitHub account, then authorize the Kiro GitHub app on
   your fork.

> Kiro needs **write** access — it works by pushing branches and opening pull requests.
> Fork rather than sharing one repo: 40 people pushing to one repo is a bad afternoon.

---

## 2. Open the network allow-list

Kiro's sandbox blocks outbound network by default. It has to, or an agent that reads a
malicious file could quietly ship your secrets somewhere. That means **your devbox is
unreachable until you allow it.**

**Settings → Agent → Network access:**

1. Set the access level to **Common dependencies** (this covers `pypi.org`, `ghcr.io`,
   `amazonaws.com`, and friends — the things `pip` and image pulls need).
2. Add a **custom allow-list** with these entries:

```
.amazoncognito.com, .llamaindex.ai, .arize.com
```

3. Add **your own devbox domain** from the card — the `FLYTE_DOMAIN` value, e.g.
   `student01.workshop.example.com`.

> **What each one is for.** `FLYTE_DOMAIN` is how Kiro submits work; `.amazoncognito.com`
> is where it gets a token. Those two are load-bearing — without them nothing runs. The
> other two are belt-and-braces for anything you decide to try directly from the sandbox.
> Most of the day, the interesting network calls (Claude, LlamaParse, Phoenix) happen from
> **task pods on your devbox**, not from here — and those pods have unrestricted egress.
> This allow-list only governs Kiro's own sandbox.

> **Don't just pick "Open internet."** It works, and it's tempting, but Kiro warns about
> it for a real reason: the agent reads untrusted content all day, and unrestricted
> egress plus the secrets you're about to add is exactly the shape of a prompt-injection
> exfiltration. The allow-list above is ~30 seconds of typing.

---

## 3. Add your secrets

**Settings → Agent → Secrets → Add secret.** One at a time, from your card:

| Secret | What it is | Looks like |
|---|---|---|
| `FLYTE_DOMAIN` | Your devbox's hostname | `student01.workshop.example.com` |
| `COGNITO_DOMAIN` | Where tokens come from | `https://flyte-devbox-1234.auth.us-east-1.amazoncognito.com` |
| `COGNITO_CLIENT_ID` | Your devbox's M2M client | `7abc…` |
| `COGNITO_CLIENT_SECRET` | …and its secret | `xyz…` |
| `AWS_ACCESS_KEY_ID` | Pushes your built images to ECR | `AKIA…` |
| `AWS_SECRET_ACCESS_KEY` | …and its secret | `…` |
| `AWS_REGION` | Where your account lives | `us-east-1` |
| `LLAMA_CLOUD_API_KEY` | For Module 10 (add it now, use it later) | `llx-…` |

Kiro injects these as environment variables into the sandbox **when a task starts**. So:

> ⚠️ **Add all eight before you start a task.** If you add a secret to a task that's
> already running, it won't see it, and you'll get a confusing "variable not set" error
> from a variable you can plainly see in Settings. Start a new task instead.

**No Claude API key?** Correct — there isn't one. In [Module 11](../modules/11-arize-phoenix.md)
your tasks call Claude through **AWS Bedrock**, using the IAM role attached to the EC2
instance your devbox runs on. The credentials are ambient. Nothing to paste, nothing to
leak, nothing to revoke. It's a genuinely nicer story than an API key on a card, and it's
what you'd want at work.

**What the AWS keys are for.** Today you'll build real container images, and they need
somewhere to live — your account's ECR registry. `bootstrap.sh` uses these to log in.
They are **scoped to pushing images to ECR and nothing else**, in an account that gets
destroyed after the event.

**On trusting the sandbox with any of this:** Kiro's own docs are blunt that an agent
*can* leak secrets it's been given, through code, logs, or requests. That's why the
allow-list in step 2 matters, and it's why none of these are long-lived credentials to
anything you care about — the Cognito client only reaches your throwaway devbox, the AWS
key only pushes images, and the whole account gets torn down after the event.

---

## 4. Add the Flyte MCP server

This is what stops Kiro from inventing Flyte APIs. **Do not skip it.**

**Settings → Agent → MCP server settings → Add server:**

| Field | Value |
|---|---|
| **Name** | `flyte` |
| **Type** | `local` |
| **Command** | `npx` |
| **Args** | `-y mcp-remote https://flyte-mcp.apps.demo.hosted.unionai.cloud/flyte-mcp/mcp` |

> **Why the weird `npx mcp-remote` wrapper?** The Flyte MCP server is *remote* (it's a
> URL, no login needed). Kiro Web currently only supports **local** MCP servers — remote
> ones aren't available yet. `mcp-remote` is a small stdio-to-HTTP bridge: Kiro talks to
> it locally, and it relays to the real server. If Kiro Web ships remote MCP support
> before August 14, you can point straight at the URL and drop the wrapper.

---

## 5. Connect to your devbox

Start a new task in Kiro and paste:

> Run `bash scripts/bootstrap.sh` and show me its full output.

That script does five things, and prints a ✅ for each: installs a `docker` shim (Flyte's
image builder wants `docker buildx`; this sandbox has podman, so we bridge the two), logs
that podman into your ECR registry, writes `.flyte/config.yaml` pointed at your devbox,
mints a Cognito token to prove auth works, and calls `flyte get config` to prove the
devbox answers.

**If it fails, read the error — it's written to tell you exactly which step broke** and
what usually causes it.

> **"It's just hanging."** Your devbox auto-stops when nobody's used it for 30 minutes,
> which is very likely true right now. The first request wakes it and takes about **2
> minutes**. Wait, then re-run. This will also happen after lunch — it's not broken.

---

## ✅ Checkpoint A: Kiro can reach your devbox

`bootstrap.sh` ends with 🎉 and prints your Flyte UI URL.

**Open that URL in a second browser tab and leave it open all day.** Log in with the
same identity. You should see the Flyte console with an empty execution list.

That tab is where you verify everything. Kiro Web has no terminal — you will never watch
a log scroll past. The Flyte UI is your terminal, and it's a better one.

---

## ✅ Checkpoint B: the MCP is live

Paste this to Kiro:

> Using the Flyte MCP server, tell me what a `TaskEnvironment` is and what `@env.task`
> does in Flyte v2. Quote the docs you found and tell me which MCP tool you called.

**A pass looks like:** specifics, quoted from real docs, and it names the MCP tool it
used.

**A fail looks like:** a fluent, plausible, confident answer with no citation — or any
mention of `@workflow`, `flytekit`, `pyflyte`, or `map_task`. Those are **Flyte v1**
APIs. They're all over the public internet, so a model with no MCP will reach for them
every time. **That's the tell.** If you see it, go back to step 4.

Ask it directly if you're unsure:

> Which MCP servers can you see right now?

---

## Both checkpoints green?

You're ready. → **[Module 01 — Your first cloud task](../modules/01-first-task.md)**

Curious what's actually running in your AWS account?
→ [01 — Meet your devbox](01-your-devbox.md)
