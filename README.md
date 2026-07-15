# Build agentic pipelines on Flyte — AWS Partner Workshop

**August 14 · Full day · Everything runs in your browser.**

You get an AWS account with a **Flyte devbox** already running in it, and you drive
it from **Kiro Web** — AWS's browser-based coding agent. No laptop setup, no Docker,
no `pip install`. Two browser tabs and you're building.

By the end of the day you'll have run Python on a real cluster, fanned it out across
hundreds of inputs, survived failures, parsed a pile of PDFs in parallel, and traced
an agent end to end — and you'll have written almost none of it by hand.

---

## How this workshop works

**You don't type code. You direct an agent that types code.**

Every module hands you a **prompt** to paste into Kiro. Kiro writes the pipeline and
runs it against your devbox. Your job is to *decide what to build*, then *prove it
actually worked*.

> **The one rule that makes this work:** Kiro's output will differ every single time,
> for every person in the room. That's fine and expected. We never check that your
> code looks a certain way. We check that **the right thing happened** — a run
> succeeded, work ran in parallel, a failure recovered. Each module ends with a
> **Checkpoint** you verify yourself.

### Two tabs, two jobs

| Tab | What it is | What you do there |
|---|---|---|
| **Kiro Web** — [app.kiro.dev](https://app.kiro.dev) | The agent. Chat, plan, build. | Paste prompts. Read what it wrote. Ask it "why?" |
| **Flyte UI** — `https://<your-domain>/v2` | Your devbox. Real executions. | **Watch things run.** This is where you verify. |

**Keep the Flyte UI open all day.** Kiro Web has no terminal — you will never watch a
log scroll by. The Flyte UI *is* your terminal, and it's a much better one: every
task, every retry, every parallel branch, every report, rendered live.

That inversion is the whole point. You direct, the agent executes, and the cluster
shows you the truth. When Kiro claims something worked, **don't take its word for
it — go look.** Checking the agent's homework is a skill worth practicing on a day
when the stakes are zero.

---

## Agenda

| Time | Module | What you'll build |
|---|---|---|
| 09:00 | [Setup](setup/) | Kiro Web wired to your devbox |
| 09:45 | [01 — Your first cloud task](modules/01-first-task.md) | Plain Python, running on a cluster |
| 10:15 | [02 — Fan out](modules/02-fan-out.md) | The same task across 100 inputs, in parallel |
| 10:45 | *break* | |
| 11:00 | [03 — Survive failure](modules/03-resilience.md) | Retries and per-task resources |
| 11:30 | [04 — See inside](modules/04-reports.md) | Live HTML reports from inside a task |
| 12:00 | *lunch* | |
| 13:00 | [05 — Deploy it](modules/05-deploy.md) | A named, reusable entity on the backend |
| 13:30 | [10 — LlamaIndex](modules/10-llamaindex.md) | Parse a stack of PDFs in parallel, cached by content |
| 15:00 | *break* | |
| 15:15 | [11 — Arize Phoenix](modules/11-arize-phoenix.md) | Deploy Phoenix to your own cluster, trace an agent into it |
| 16:30 | [99 — Now you drive](modules/99-now-you-drive.md) | Build something of your own |

Partner tracks still cooking — see [`modules/`](modules/) for
[Protopia](modules/20-protopia.md), [CloudZero](modules/21-cloudzero.md), and
[Portal26](modules/22-portal26.md) stubs.

---

## Start here

👉 **[setup/](setup/)** — about 20 minutes, mostly clicking. Do it before Module 01.

Everything after setup assumes two things are true:
1. Kiro can reach your devbox (Setup Checkpoint A).
2. Kiro can reach the Flyte MCP server (Setup Checkpoint B).

If either is false, later modules fail in confusing ways. Don't skip the checkpoints.

---

## What is this stuff?

**Flyte** is an orchestrator. You write normal Python functions, mark them as tasks,
and Flyte runs them on real infrastructure — with parallelism, retries, caching, and
observability that you don't have to build.

**Devbox** is a whole Flyte cluster on one EC2 box. Real k3s, real object storage,
real executions — just small and cheap and yours. It auto-stops when idle.

**Kiro Web** is an agentic IDE in your browser. It clones your repo into a sandbox,
writes code, runs it, and opens pull requests.

**The Flyte MCP server** is what keeps Kiro honest. It gives the agent live access to
Flyte's real docs and APIs. Without it, agents confidently invent Flyte APIs that have
never existed. With it, they write current, correct code. This is why setup matters.

---

## Getting unstuck

- **Kiro says it worked but the UI shows nothing.** Trust the UI. Ask Kiro:
  *"Show me the exact command you ran and its full output."*
- **Kiro is inventing Flyte APIs.** Its MCP connection is broken. Redo
  [Setup Checkpoint B](setup/00-kiro-web.md#-checkpoint-b-the-mcp-is-live).
- **Everything hangs.** Your devbox auto-stops when idle. The first request wakes it
  (~2 min). Wait, then retry.
- **Still stuck?** Grab a facilitator. Seriously — don't burn 20 minutes solo.

## After today

- Flyte examples: https://github.com/flyteorg/flyte-sdk/tree/main/examples
- Flyte docs: https://www.union.ai/docs/v2/flyte/
- Slack: https://slack.flyte.org/
- Deploy your own devbox: https://github.com/unionai-oss/flyte-aws-marketplace
