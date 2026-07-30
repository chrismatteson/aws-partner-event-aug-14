# Build agentic pipelines on Flyte -- AWS Partner Workshop

**August 14 · Full day · Everything runs in your browser.**

You get an AWS account with a **Flyte devbox** already running in it, and you drive
it from **Kiro Web** -- AWS's browser-based coding agent. No laptop setup, no Docker,
no `pip install`. Two browser tabs and you're building.

By the end of the day you'll have run Python on a real cluster, fanned it out across
hundreds of inputs, survived failures, parsed a pile of PDFs in parallel, and traced
an agent end to end -- and you'll have written almost none of it by hand.

---

## How this workshop works

**You don't type code. You direct an agent that types code.**

Every module gives you a **task** to accomplish, **hints** to guide your prompt, and a
**stretch** question to deepen your understanding. Your job is to read the context,
construct a prompt that gets Kiro to build the right thing, then *prove it actually
worked* in the Flyte UI.

> **The one rule that makes this work:** Kiro's output will differ every single time,
> for every person in the room. That's fine and expected. We never check that your
> code looks a certain way. We check that **the right thing happened** -- a run
> succeeded, work ran in parallel, a failure recovered. Each module ends with a
> **Checkpoint** you verify yourself.

### How to use this workshop

Your workflow for every section follows the same loop:

1. **Read the module.** Each section gives you context about *what* you are building and *why* it matters. Read it before you prompt -- it tells you what to ask for.
2. **Write your own prompt.** The task box tells you what to accomplish. The hints tell you what concepts matter. You put those together into a prompt for Kiro -- there is no single right answer.
3. **Verify in the Flyte UI.** Every section has a checkpoint. Go look at the execution in the Flyte UI and confirm the right thing happened. Do not take Kiro's word for it.
4. **Ask why.** The stretch question is there to make you curious. Ask Kiro to explain the thing you just built so you understand it, not just so you saw it work.
5. **Move on.** Once the checkpoint is green, move to the next section.

The modules get progressively less guided. Module 01 gives you generous hints; by the partner tracks you are expected to figure out more on your own.

### Two tabs, two jobs

| Tab | What it is | What you do there |
|---|---|---|
| **Kiro Web** -- [app.kiro.dev](https://app.kiro.dev) | The agent. Chat, plan, build. | Write prompts. Read what it wrote. Ask it "why?" |
| **Flyte UI** -- `https://<your-domain>/v2` | Your devbox. Real executions. | **Watch things run.** This is where you verify. |

**Keep the Flyte UI open all day.** Kiro Web has no terminal -- you will never watch a
log scroll by. The Flyte UI *is* your terminal, and it's a much better one: every
task, every retry, every parallel branch, every report, rendered live.

That inversion is the whole point. You direct, the agent executes, and the cluster
shows you the truth. When Kiro claims something worked, **don't take its word for
it -- go look.** Checking the agent's homework is a skill worth practicing on a day
when the stakes are zero.

---

## Agenda

| Time | Module | What you'll build |
|---|---|---|
| 09:00 | [Setup](setup/) | Kiro Web wired to your devbox |
| 09:30 | [01 -- Your first cloud task](modules/01-first-task.md) | Plain Python, running on a cluster |
| 10:00 | [02 -- Fan out](modules/02-fan-out.md) | The same task across 200 inputs, in parallel |
| 10:30 | *break* | |
| 10:45 | [03 -- Survive, see, and ship](modules/03-resilience.md) | Retries, live reports, and deploy |
| 11:30 | [10 -- LlamaIndex](modules/10-llamaindex.md) | Parse a stack of PDFs in parallel, cached by content |
| 12:30 | *lunch* | |
| 13:30 | [11 -- Arize Phoenix](modules/11-arize-phoenix.md) | Deploy Phoenix to your own cluster, trace an agent into it |
| 14:30 | *break* | |
| 14:45 | [99 -- Now you drive](modules/99-now-you-drive.md) | Build something of your own |

Partner tracks still cooking -- see [`modules/`](modules/) for
[Protopia](modules/20-protopia.md), [CloudZero](modules/21-cloudzero.md), and
[Portal26](modules/22-portal26.md) stubs.

---

## Start here

👉 **[setup/](setup/)** -- one deploy command, then ~5 minutes of clicks in Kiro Web. Do it
before Module 01.

Everything after setup assumes two things are true:
1. Kiro can reach your devbox (Setup Checkpoint A).
2. Kiro can reach the Flyte MCP server (Setup Checkpoint B).

If either is false, later modules fail in confusing ways. Don't skip the checkpoints.

---

## What is this stuff?

**Flyte** is an orchestrator. You write normal Python functions, mark them as tasks,
and Flyte runs them on real infrastructure -- with parallelism, retries, caching, and
observability that you don't have to build.

**Devbox** is a whole Flyte cluster on one EC2 box. Real k3s, real object storage,
real executions -- just small and cheap and yours. It auto-stops when idle.

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
  [Setup Checkpoint B](setup/README.md#-checkpoint-b-the-mcp-is-live).
- **Everything hangs.** The first request of the day can be slow while the cluster comes
  up. (If auto-stop was enabled — it's off by default — the first request after ~30 min
  idle wakes the box, ~2 min.) Wait, then retry.
- **Still stuck?** Grab a facilitator. Seriously -- don't burn 20 minutes solo.

## After today

- Flyte examples: https://github.com/flyteorg/flyte-sdk/tree/main/examples
- Flyte docs: https://www.union.ai/docs/v2/flyte/
- Slack: https://slack.flyte.org/
- Deploy your own devbox: https://github.com/unionai-oss/flyte-aws-marketplace
