# Setup

Two parts: **stand up the account** (one CloudFormation command), then **wire up Kiro Web**
with the values it prints. If someone already handed you a role ARN and a Flyte login, skip
to [Part 2](#part-2--wire-up-kiro-web).

---

## Part 1 — Deploy the workshop stack

Whoever provisions the account runs this once. It needs AWS CLI v2 with credentials for the
target account, and a Route 53 hosted zone that your chosen hostname sits under.

```bash
bash provisioning/deploy.sh <flyte-domain> <attendee-email> [llama-cloud-key]

# e.g.
bash provisioning/deploy.sh student01.flytedemo.app you@example.com llx-abc123
```

It runs two CloudFormation stacks — the Flyte devbox and the Kiro provisioning — and prints
everything Part 2 needs:

- **Sandbox IAM Role ARN**
- **Flyte UI URL**
- **Flyte login** (email + password)
- the **network allow-list** (the same two domains for everyone)

> **The box doesn't sleep by default.** Deploy defaults to `AUTOSTOP=No`, so there are no
> ~2-minute wake delays mid-workshop. For a long-lived box you want cheap when idle, deploy
> with `AUTOSTOP=Yes bash provisioning/deploy.sh …` (it stops after ~30 min idle and wakes
> on the next request). Prerequisites and the per-stack breakdown:
> [provisioning/README.md](../provisioning/README.md).

---

## Part 2 — Wire up Kiro Web

You need two things from Part 1: the **role ARN** and your **Flyte login**. No secrets to
type beyond the ARN — everything else the sandbox fetches for itself. About five minutes.

### 1. Sign in and connect the repo

1. Go to **[app.kiro.dev](https://app.kiro.dev)** and sign in.
2. Connect **GitHub** when prompted.
3. **Fork this repo** to your own account, then pick your fork as the repo for this task.

> Kiro needs **write** access — it works by pushing branches and opening pull requests, and
> GitHub bundles those permissions together. A fork keeps that access on a throwaway copy
> that's yours; 40 people sharing one repo would collide all afternoon.

### 2. Set the sandbox IAM role

This is the one value you paste, and it's what makes everything else automatic. The role
lets your sandbox reach *your* AWS account — to read its config and push images — with
short-lived credentials instead of pasted keys.

**Settings → Agent → Sandbox → IAM Role**, paste the **role ARN**, save. Kiro validates it.

> **Why a role instead of secrets?** An agent that reads untrusted files all day is exactly
> what you don't want holding long-lived API keys. The role gives temporary credentials,
> scoped to just two things in a throwaway account: push images to your registry, and read
> your workshop config. Nothing to leak that outlives the day.

### 3. Open the network allow-list

Kiro's sandbox blocks outbound network by default — it has to, or an agent that reads a
malicious file could ship your data somewhere. So you open exactly what's needed.

**Settings → Agent → Network access:**

1. Set the level to **Common dependencies** (covers `pypi.org`, `ghcr.io`, and all of
   `amazonaws.com` — pip, ECR, SSM, STS).
2. Add a **custom allow-list** with the two domains from the deploy output. They're the
   **same for everyone in the room** — something like:

```
.flytedemo.app, .amazoncognito.com
```

The first is where every devbox lives; `.amazoncognito.com` is where auth tokens come from.
Both are load-bearing — without them, nothing runs.

> **Don't reach for "Open internet."** It works and it's tempting, but Kiro warns about it
> for a real reason: an agent reading untrusted content with unrestricted egress is the
> exfiltration path. Two domains is thirty seconds of typing. Note also that the day's
> interesting calls — Claude, LlamaParse, Phoenix — happen from **task pods on your
> devbox**, which have their own egress; this list only governs Kiro's own sandbox.

### 4. Add the Flyte MCP server

This is what stops Kiro inventing Flyte APIs that never existed. **Do not skip it** — it's
the difference between correct code and confident fiction.

**Settings → Agent → MCP server settings → Add server:**

| Field | Value |
|---|---|
| **Name** | `flyte` |
| **Type** | `local` |
| **Command** | `npx` |
| **Args** | `-y mcp-remote https://flyte-mcp.apps.demo.hosted.unionai.cloud/flyte-mcp/mcp` |

> **Why the `npx mcp-remote` wrapper?** The Flyte MCP server is *remote* (a URL, no login).
> Kiro Web currently supports only **local** MCP servers, so `mcp-remote` bridges the two:
> Kiro talks to it locally, it relays to the real server. If Kiro Web ships remote MCP
> before the event, you can point straight at the URL and drop the wrapper.

### 5. Connect to your devbox

Start a task in Kiro and paste:

> Run `bash scripts/bootstrap.sh` and show me its full output.

> **This one task is your whole workshop.** Everything today happens in this session — keep
> it open and keep working in it. It's a single sandbox that remembers what you've built, so
> you run setup once, here, and never again. (If you ever *do* have to start a new task —
> you closed the tab, say — just re-run `bootstrap.sh` in it; it's quick and safe to repeat.)

The script confirms the role works, reads your config from AWS, installs the build shim,
logs in to your registry, and proves it can reach your devbox — printing a ✅ for each step.
**If anything fails, it tells you exactly which step and why.**

> **"It's just hanging."** The first request can take a moment while the devbox comes up. If
> your box was deployed with auto-stop enabled (it's **off by default**), the first request
> after ~30 minutes idle wakes it and takes ~2 minutes — wait, then re-run.

---

## ✅ Checkpoint A: Kiro can reach your devbox

`bootstrap.sh` ends with 🎉 and prints your Flyte UI URL.

**Open that URL in a second browser tab and leave it open all day.** Log in with the Flyte
email + password from the deploy output; you'll see an empty execution list. That tab is
where you verify everything — Kiro Web has no terminal, so the Flyte UI *is* your terminal,
and a better one.

---

## ✅ Checkpoint B: the MCP is live

Paste to Kiro:

> Using the Flyte MCP server, tell me what a `TaskEnvironment` is and what `@env.task`
> does in Flyte v2. Quote the docs you found and name the MCP tool you called.

**Pass:** specifics, quoted from real docs, with the tool named.

**Fail:** a fluent, confident answer with no citation — or any mention of `@workflow`,
`flytekit`, `pyflyte`, or `map_task`. Those are **Flyte v1** APIs, all over the public
internet, and a model with no MCP reaches for them every time. That's the tell. If you see
it, redo step 4.

---

## Both green?

You're ready. → **[Module 01 — Your first cloud task](../modules/01-first-task.md)**
