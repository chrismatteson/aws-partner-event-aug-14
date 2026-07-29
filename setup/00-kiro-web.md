# Setup — wire up Kiro Web

Your facilitator gave you a **card** with two things: the identity to sign in with, and
one **role ARN**. That's it — no secrets to type. Everything else your sandbox needs, it
fetches for itself once it can reach your AWS account.

Four short steps, about five minutes.

---

## 1. Sign in and connect the repo

1. Go to **[app.kiro.dev](https://app.kiro.dev)** and sign in with the identity from your card.
2. Connect **GitHub** when prompted.
3. **Fork this repo** to your own account, then pick your fork as the repo for this task.

> Kiro needs **write** access — it works by pushing branches and opening pull requests, and
> GitHub bundles those permissions together. A fork keeps that access on a throwaway copy
> that's yours; 40 people sharing one repo would collide all afternoon.

---

## 2. Set the sandbox IAM role

This is the one value from your card, and it's what makes everything else automatic. The
role lets your sandbox reach *your* AWS account — to read its config and push images —
with short-lived credentials instead of pasted keys.

**Settings → Agent → Sandbox → IAM Role**, paste the **role ARN** from your card, save.
Kiro validates it on save.

> **Why a role instead of secrets?** An agent that reads untrusted files all day is exactly
> what you don't want holding long-lived API keys. The role gives temporary credentials,
> scoped to just two things in a throwaway account: push images to your registry, and read
> your workshop config. Nothing to leak that outlives the day.

---

## 3. Open the network allow-list

Kiro's sandbox blocks outbound network by default — it has to, or an agent that reads a
malicious file could ship your data somewhere. So you open exactly what's needed.

**Settings → Agent → Network access:**

1. Set the level to **Common dependencies** (covers `pypi.org`, `ghcr.io`, and all of
   `amazonaws.com` — pip, ECR, SSM, STS).
2. Add a **custom allow-list** with the two domains your facilitator gives you. They're the
   **same for everyone in the room** — something like:

```
.workshop.example.com, .amazoncognito.com
```

`.workshop.example.com` is where every devbox lives; `.amazoncognito.com` is where auth
tokens come from. Both are load-bearing — without them, nothing runs.

> **Don't reach for "Open internet."** It works and it's tempting, but Kiro warns about it
> for a real reason: an agent reading untrusted content with unrestricted egress is the
> exfiltration path. Two domains is thirty seconds of typing. Note also that the day's
> interesting calls — Claude, LlamaParse, Phoenix — happen from **task pods on your
> devbox**, which have their own egress; this list only governs Kiro's own sandbox.

---

## 4. Add the Flyte MCP server

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

---

## 5. Connect to your devbox

Start a task in Kiro and paste:

> Run `bash scripts/bootstrap.sh` and show me its full output.

> **This one task is your whole workshop.** Everything today happens in this session — keep
> it open and keep working in it. It's a single sandbox that remembers what you've built,
> so you run setup once, here, and never again. (If you ever *do* have to start a new
> task — you closed the tab, say — just re-run `bootstrap.sh` in it; it's quick and safe to
> repeat.)

The script confirms the role works, reads your config from AWS, installs the build shim,
logs in to your registry, and proves it can reach your devbox — printing a ✅ for each
step. **If anything fails, it tells you exactly which step and why.**

> **"It's just hanging."** Your devbox auto-stops after 30 minutes idle, which is very
> likely true right now. The first request wakes it (~2 min). Wait, re-run. This happens
> again after lunch — it's not broken.

---

## ✅ Checkpoint A: Kiro can reach your devbox

`bootstrap.sh` ends with 🎉 and prints your Flyte UI URL.

**Open that URL in a second browser tab and leave it open all day.** Sign in with the same
identity; you'll see an empty execution list. That tab is where you verify everything —
Kiro Web has no terminal, so the Flyte UI *is* your terminal, and a better one.

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

Curious what's running in your AWS account? → [Meet your devbox](01-your-devbox.md)
