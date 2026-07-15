# 22 — Portal26: governing agents that spend money

> 🚧 **Stub — not a hands-on module yet.** Read it as background; there's nothing to run.
> The **build-it-yourself** section at the bottom is real, though, and it's a good
> [Module 99](99-now-you-drive.md) project.

## The problem

Two problems, actually, and only one of them is ours.

**Shadow AI** — people using AI tools nobody approved. Portal26's core product finds
these by ingesting from network and security infrastructure you already run (ZScaler,
Netskope, Palo Alto, Cloudflare), plus cloud provider logs, plus OpenTelemetry. That's a
network-visibility problem and it isn't Flyte's surface.

**Runaway agents** — an agent loops, calls a tool 4,000 times, and burns $9,000 before
anyone notices on Monday. That one *is* our surface, because the runaway happens inside
the orchestrator.

## Portal26's answer

**Agentic Token Controls**, announced April 2026: token limits at the agent, workflow,
and org level, that throttle or pause runaway agents. Real-time governance, policy-based
limits, cost predictability.

⚠️ **Caveat, stated plainly:** every substantive detail traces back to a single press
release. There's no product documentation, no API reference, no third-party technical
writeup. Treat it as *announced GA*, not *verified shipped*.

They also launched a **free tier for Claude governance** (June 2026) — discovery, agent
access graphs, tool-call visibility, token usage and cost. It's real, but it's a
lead-capture form asking company size and monitored-user count, and it almost certainly
needs org admin rights to read usage. Not a cold start for a workshop attendee.

## Why it's a stub

The free tier is gated behind a form and a qualification conversation. Nothing an
attendee can stand up in twenty minutes.

## Build it yourself — this one's actually good

Here's the thing: **token budgets belong in the orchestrator.** A governance tool watching
from outside can tell you an agent burned $9,000. Flyte can *stop it at $50*, because
Flyte is the thing running the agent. Detection versus enforcement, and enforcement needs
to live where the work happens.

So build it:

> Write a Flyte task that wraps an LLM call with a budget guard. Key the budget on the
> execution ID from the run context. Count tokens as you go. When the budget is
> exceeded, fail the task — loudly. Then write a deliberately runaway agent loop and
> watch Flyte hard-stop it mid-run.

Everything you need is in Modules [01](01-first-task.md)–[03](03-resilience.md). It's a
`@env.task` with a counter, `flyte.ctx()` for the execution ID, and a raise.

Then push on it, because the interesting part is where it gets hard:

- **Per-task budgets are easy. Per-workflow budgets are a shared-counter problem** —
  where does the count live when 200 mapped tasks are spending in parallel?
- **Retries re-spend.** A task that burns 10k tokens and fails burns 10k more on retry.
  Does your budget know that? (Remember from Module 03: every retry is a fresh pod.)
- **Throttle or kill?** Killing is easy and sometimes wrong. Pausing for human review is
  harder and usually righter.

Those three questions are the entire product category, and you can feel all of them in
about forty minutes.

## Status

Chris is working the Portal26 relationship. The most likely real track pairs *their*
detection with *our* enforcement — they see every agent in the org, Flyte stops the ones
that matter. That's a genuinely complementary story rather than an overlap.
