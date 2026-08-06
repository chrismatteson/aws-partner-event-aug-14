# Build agentic pipelines on Flyte — AWS Partner Workshop

**August 14 · Full day · Everything runs in your browser.**

You get an AWS account with a **Flyte devbox** already running in it, and you drive it from
**Kiro Web** — AWS's browser-based coding agent. No laptop setup. Two browser tabs and
you're building.

By the end of the day you'll have run Python on a real cluster, fanned it out across
hundreds of inputs, survived failures, and traced an agent end to end — and written almost
none of it by hand.

---

## How this works

**You don't type code. You direct an agent that types code.** Each module gives you a
**task**, **hints**, and a **stretch** question. You turn those into a prompt, then *prove
it worked* in the Flyte UI.

Kiro's output differs every time, for every person — that's expected. We never check that
your code looks a certain way. We check that **the right thing happened**: a run succeeded,
work ran in parallel, a failure recovered. Each module ends with a **Checkpoint** you verify
yourself.

### Two tabs, two jobs

| Tab | What it is | What you do there |
|---|---|---|
| **Kiro Web** | The agent. Chat, plan, build. | Write prompts. Read what it wrote. Ask "why?" |
| **Flyte UI** — `https://<your-domain>/v2` | Your devbox. Real executions. | **Watch things run.** This is where you verify. |

**Keep the Flyte UI open all day.** Kiro has no terminal — the Flyte UI *is* your terminal,
and a better one: every task, retry, and parallel branch rendered live. When Kiro says
something worked, **go look** instead of taking its word.

---

## Setup

You have a card (or the CloudFormation **Outputs**) with these values: `KiroLoginUrl`,
`KiroStartUrl`, `KiroRegion`, `KiroLoginEmail`, `KiroPassword`, `KiroSandboxRoleArn`, plus
`FlyteUiUrl` / `FlyteLoginEmail` / `FlytePassword`. About five minutes.

### 1. Sign in to Kiro

Open **`KiroLoginUrl`** and choose **"Sign in with your organization."** Enter your
**`KiroStartUrl`** and pick region **`KiroRegion`**, then sign in with **`KiroLoginEmail`**
and **`KiroPassword`** (you'll set a new password on first sign-in).

> 📸 _Screenshot: the "your organization" sign-in screen with start URL + region._

### 2. Configure the sandbox

All under **Settings → Agent**.

**a. Network access → allow all outbound internet.**

> 📸 _Screenshot: network access set to allow all outbound._

**b. MCP servers → add a server.** Paste this — it's what keeps Kiro honest about Flyte's
API (without it, agents confidently invent Flyte calls that never existed):

```json
{
  "mcpServers": {
    "flyte": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://flyte-mcp.apps.demo.hosted.unionai.cloud/flyte-mcp/mcp"]
    }
  }
}
```

> 📸 _Screenshot: the MCP servers panel with `flyte` connected (green)._

**c. Sandbox → IAM Role.** Paste your **`KiroSandboxRoleArn`** and save. This is what lets
the sandbox reach *your* AWS account with short-lived credentials — no keys to paste.

> 📸 _Screenshot: the IAM Role field with the ARN pasted._

**d. Steering files → add.** Open
**[.kiro/steering/workshop.md](.kiro/steering/workshop.md)**, copy the **whole file**, and
paste it in. This is the agent's rulebook and its devbox-connection script.

> 📸 _Screenshot: the steering files panel with the workshop file pasted in._

### 3. Connect to your devbox

Start a task and prompt:

> Connect to my devbox.

The steering tells Kiro how: it reads your config from AWS, writes the Flyte config, logs in
to your registry, and calls the devbox — printing a ✅ when it's connected. The first call
can take ~2 minutes while the box wakes.

**✅ Checkpoint A — connected.** Kiro reports `✅ Connected` and a Flyte UI URL.

### 4. Open the Flyte UI tab

Open **`FlyteUiUrl`** in a second tab and log in with **`FlyteLoginEmail`** /
**`FlytePassword`**. You'll see an empty execution list. Leave this tab open all day — it's
where you verify everything.

**✅ Checkpoint B — MCP is live.** Paste to Kiro:

> Using the Flyte MCP server, tell me what a `TaskEnvironment` is and what `@env.task` does
> in Flyte v2. Quote the docs and name the MCP tool you called.

**Pass:** specifics, quoted from real docs, tool named. **Fail:** a fluent answer with no
citation, or any mention of `@workflow`, `flytekit`, `pyflyte`, or `map_task` — those are
Flyte **v1**, the tell of a broken MCP. If you see it, redo step 2b.

Both green? → **[Module 01](modules/01-first-task.md)**.

---

## Agenda

| Time | Module | What you'll build |
|---|---|---|
| 09:00 | Setup (above) | Kiro wired to your devbox |
| 09:30 | [01 — Your first cloud task](modules/01-first-task.md) | Plain Python, running on a cluster |
| 10:00 | [02 — Fan out](modules/02-fan-out.md) | The same task across 200 inputs, in parallel |
| 10:45 | [03 — Survive, see, and ship](modules/03-resilience.md) | Retries, live reports, and deploy |
| 11:30 | [10 — LlamaIndex](modules/10-llamaindex.md) ⚠️ | Parse a stack of PDFs in parallel _(currently unavailable)_ |
| 13:30 | [11 — Arize Phoenix](modules/11-arize-phoenix.md) ⚠️ | Trace an agent into Phoenix _(currently unavailable)_ |
| 14:45 | [99 — Now you drive](modules/99-now-you-drive.md) | Build something of your own |

> ⚠️ **Modules 10 and 11 are currently unavailable** while their data/setup is reworked.

---

## What is this stuff?

- **Flyte** — an orchestrator. Write normal Python functions, mark them as tasks, and Flyte
  runs them on real infrastructure with parallelism, retries, caching, and observability you
  don't have to build.
- **Devbox** — a whole Flyte cluster on one EC2 box: real k3s, real object storage, real
  executions, just small and yours.
- **Kiro Web** — an agentic IDE in your browser. It writes code, runs it, and can open PRs.
- **The Flyte MCP server** — gives Kiro live access to Flyte's real docs and APIs so it
  writes current, correct code instead of inventing v1 APIs. This is why setup step 2b matters.

---

## Getting unstuck

- **Kiro says it worked but the UI shows nothing.** Trust the UI. Ask: *"Show me the exact
  command you ran and its full output."*
- **Kiro is inventing Flyte APIs.** Its MCP connection is broken — redo Checkpoint B.
- **Everything hangs.** The first request of the day is slow while the cluster wakes (~2 min).
  Wait, then retry.
- **Still stuck?** Grab a facilitator — don't burn 20 minutes solo.

## After today

- Flyte examples: https://github.com/flyteorg/flyte-sdk/tree/main/examples
- Flyte docs: https://www.union.ai/docs/v2/flyte/
- Slack: https://slack.flyte.org/
- Deploy your own devbox: https://github.com/unionai-oss/flyte-aws-marketplace
