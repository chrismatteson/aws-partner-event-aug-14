# 11 -- Arize Phoenix: trace an agent running inside Flyte

> ⚠️ **This module is currently unavailable** while its setup is reworked. Skip to
> [Module 99](99-now-you-drive.md).

**~60 minutes.** You'll add a third browser tab — and deploy the thing behind it yourself.

By now you've watched a lot of work run in the Flyte UI: what started, whether it retried,
how long it took, what it returned. That's orchestration, and it's most of what you need —
right up until the thing inside the task is an LLM. Then the questions change. The task
went green in 8 seconds. Fine. But *what did you actually send the model?* How many tokens?
The agent called three tools — which one earned its keep, which wasted a round trip? Why did
this run cost nine cents and the identical one beside it cost two? Flyte can't tell you, and
it shouldn't try: to Flyte your task is a black box that exited 0.

**Arize Phoenix** opens the box. It's an LLM-observability tool built on OpenTelemetry: your
code emits *spans* — one per model call, one per tool call, nested to match the agent — and
Phoenix renders them as a clickable tree with the full prompt, completion, token counts, and
latency on every node. And you're going to run it **on your own devbox, as a Flyte app** —
no hosted account, no signup, no quota, traces never leaving your AWS account.

The real lesson underneath the three tasks: **Flyte and Phoenix answer different questions,
and you want both.** Flyte tells you *the run* happened (retries, parallelism, resources).
Phoenix tells you *what the model did* inside it. You'll finish with both open, showing the
same executions from two angles, joined by an ID you stamp yourself.

> **A licensing aside.** Phoenix is Elastic License 2.0 — not OSI-approved. Self-hosting it
> for your own team (exactly what you're about to do) is squarely fine; just know it if your
> org only permits OSI licenses. And if you *didn't* have a cluster, `app.phoenix.arize.com`
> is the self-serve hosted option — not what we're using here.

---

## 1. Deploy Phoenix onto your own cluster

In Module 03 you used `flyte deploy` to register a *task*. Hold that thought — the same verb
ships a whole **web service**. Flyte v2 has a second kind of environment: a `TaskEnvironment`
describes work that runs and exits; an **`AppEnvironment`** describes a long-running service
that stays up and answers requests. Underneath it's Knative, enabled on your devbox by
default. Phoenix is just a container that serves a UI and an OTLP receiver — so it's an app
you deploy.

Fair warning: this is new ground. There's no reference repo to copy, so lean on the hints and
confirm the shape against the MCP.

> **Your task:** Create `work/phoenix_app.py` that deploys Phoenix as a Flyte app, deploy it
> with `flyte deploy`, and find the app's URL.
>
> **Hints:** It's `flyte.app.AppEnvironment` — **not** `flyte.app.App`, which doesn't exist
> (a natural thing for an agent to invent; if Kiro reaches for it, that's the MCP not being
> consulted). Confirm `flyte.app` against the MCP. Pin the published image
> `docker.io/arizephoenix/phoenix:latest` by reference (`from_base` — nothing to build, it's
> someone else's image); expose port **6006**. Two things are load-bearing and easy to get
> wrong: the image is **distroless** (no `/bin/sh`), so it needs an explicit `command` that
> runs the Phoenix server module directly — a shell-form command CrashLoops; and set scaling
> to a fixed **one replica** — the default scales to zero, storage here is ephemeral, and an
> idle Phoenix takes all your traces with it. Get the URL from the Flyte UI or MCP, don't
> guess a pattern.
>
> **Stretch:** Ask Kiro how `AppEnvironment` differs from `TaskEnvironment`, and what the
> other names in `flyte.app` (`Scaling`, `Port`, `AppEndpoint`, …) are for.

### ✅ Checkpoint 1: Phoenix is running on your devbox

- **Flyte UI**: the `phoenix` app is listed and healthy, one replica up.
- **Phoenix UI**: open the URL Kiro found. You get the Phoenix interface with an empty project
  list. Leave this tab open — it's your third tab for the rest of the day.

Sit with that a second: you deployed a real web service — database, HTTP server, frontend —
onto a Kubernetes cluster from a browser, without a Dockerfile, a `kubectl` command, a line of
YAML, or a terminal. Same `flyte deploy` as Module 03; the unit changed, the workflow didn't.
Note what you *didn't* do: build anything. **Build when the image is yours, pin when it's
someone else's.**

---

## 2. Trace one LLM call — and beat the flush gotcha

Now send Phoenix a span from a task on the same cluster. The LLM call goes through **Bedrock**
(no API keys — the task pod uses the devbox's instance role), and you instrument it with
OpenTelemetry so every call becomes a span.

This task has a trap built into it on purpose, because it's the most transferable thing in the
module.

> **Your task:** Create `work/trace_one.py` with a task that makes one Claude call and sends a
> trace to your Phoenix app. Confirm the span shows up in the Phoenix UI — the prompt, the
> completion, the token counts.
>
> **Hints:** Call Claude with `AnthropicBedrockMantle`, model `anthropic.claude-sonnet-5` — a
> **bare** id, no `us.` prefix and no `-v1:0` suffix (the legacy form fails here); set
> `AWS_REGION` in the task env. Instrument with `arize-phoenix-otel` (its `register()`) plus
> `openinference-instrumentation-anthropic`. Export **OTLP over HTTP** to your Phoenix app's
> **in-cluster** address on **port 80** at `/v1/traces` — not the public URL, not gRPC/4317.
> In-cluster traffic goes pod-to-pod and never touches the ALB, so there's no auth to deal
> with; have Kiro derive the in-cluster service DNS name (confirm the pattern via the MCP)
> rather than guessing.
>
> 🔴 **The flush gotcha — the heart of this module.** OpenTelemetry's default batch span
> processor buffers spans and exports them on a background timer. A **short-lived process that
> exits before that timer fires drops its spans silently** — no error, no warning, an empty
> Phoenix. Flyte tasks are short-lived by design, so this *will* bite you. The fix: disable
> batching (export each span immediately) or flush/shut down the tracer explicitly before the
> task returns. Try it the naive way first and watch the UI stay empty — then fix it.

### ✅ Checkpoint 2: a span from your cluster, in your Phoenix

The Phoenix UI shows a trace from your task — the model call, the prompt and completion, token
counts and latency. It came from a pod on your own devbox.

### 💡 Understand

You just met a failure mode with no error message. Keep count — this module has **three ways
to end up staring at an empty Phoenix and no traceback**:

1. **Missing instrumentor** — the openinference package isn't installed, so nothing is
   patched, so no spans.
2. **Wrong instrumentor** — `openinference-instrumentation-bedrock` sounds right but it
   instruments boto3's Bedrock client, not `AnthropicBedrockMantle`; it produces **zero
   spans, silently**. You want `-anthropic`.
3. **Unflushed batch** (above) — and a fourth cousin, the scale-to-zero Phoenix from Task 1.

They rhyme, and the rhyme is the lesson: **observability tooling fails silently by design.**
You verify it's working by *looking*, never by the absence of an error. Which is the same
habit you've practiced all day in the Flyte UI.

---

## 3. Trace an agent, and join it to Flyte

One span is a demo. The payoff is a whole **agent** — several model calls and tool calls,
nested — rendered as a tree, and then fanned out so you can see many of them at once and pivot
between the two UIs.

> **Your task:** Write (or reuse) a small multi-step, tool-calling agent as a Flyte task —
> for example over the PDFs you parsed in [Module 10](10-llamaindex.md) — trace it into
> Phoenix, then `flyte.map` it across several inputs. Stamp each trace with its Flyte
> **execution ID** so you can jump from a Phoenix trace to the exact Flyte execution that
> produced it.
>
> **Hints:** Auto-instrumentation will pick up the agent's calls once the right openinference
> package is installed — no per-call wiring. For the join, read the execution ID from the run
> context (`flyte.ctx()` — confirm the attribute via the MCP) and set it as a span attribute.
> Watch the flush gotcha again: each mapped task is its own short-lived process.
>
> **Stretch:** Open the same fan-out in both tabs. Ask yourself which question each UI answers
> — and stamp one more attribute (say, the input's name) so you can find a specific trace fast.

### ✅ Checkpoint 3: two UIs, one system

- **Phoenix**: a span *tree* for one agent run — model calls and tool calls nested — and
  **N** traces from the mapped fan-out.
- **The join**: pick a Phoenix trace, read its execution-ID attribute, find that exact
  execution in the Flyte UI. Flyte shows you the orchestration (did it retry? run in
  parallel? what did it cost in compute?); Phoenix shows you the semantics (what did the model
  actually do?). Different questions, same run — and now you can move between them.

---

## Push it further

- **Prove the silent failures.** Deliberately install `-bedrock` instead of `-anthropic`, or
  leave batching on, and watch Phoenix stay empty with a green Flyte run. Feel how nothing
  tells you — that's the whole point.
- **Chart it back in Flyte.** Pull token counts or latencies out of your agent runs and emit a
  `flyte.report` (Module 03) summarizing them — Flyte's operational view and Phoenix's semantic
  view, stitched into one artifact that travels with the execution.
- **Add an eval.** Score each agent output and trace the score as a span attribute, so a bad
  run is findable in Phoenix, not just a number in a table.

---

That's the arc: you ran Python on a cluster, scaled it, hardened it, shipped it, parsed a pile
of documents cheaply, and traced an agent end to end — and you wrote almost none of it by hand.
**Next:** [99 -- Now you drive](99-now-you-drive.md).
