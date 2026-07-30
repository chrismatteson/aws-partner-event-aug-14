# 03 -- Survive, see, and ship

**~45 minutes.**

Modules 01 and 02 got your code running and scaling. Production asks for three more
things: it has to **survive failures**, let you **see inside** it, and **outlive your
session**. That's this module — three tasks, each one a thing you'd otherwise build
yourself.

---

## 1. Survive failure

Real pipelines fail. A model API rate-limits you, a spot instance vanishes, one PDF in
ten thousand is malformed. The question isn't how to prevent it — it's whether a
transient blip costs you the whole run.

The trick you'll hit: **every retry runs in a fresh pod**, with fresh memory and a fresh
filesystem. A counter variable (`attempts += 1`) resets to zero on every attempt, so the
task fails identically forever and looks like retries are broken. The task has to read
the attempt number Flyte *hands* it. That's the shape of every distributed-retry bug
you'll ever write — cheaper to meet here than at 2am.

> **Your task:** Create `work/resilient.py` with a task that deliberately fails on its
> first attempt and succeeds when retried. It must detect its current attempt number from
> Flyte — not from a local variable — and use that to decide whether to fail. Configure
> retries so the run recovers. Run it and confirm the final status.
>
> **Hints:** Each retry is a new pod; local state doesn't survive. Ask the MCP how a task
> reads its current attempt number, and where `retries` goes in Flyte v2 — it is **not**
> on the `TaskEnvironment` (that's the single most common v2 mistake; models reach for the
> v1 spot). If Kiro puts `retries` on the environment, point it back at the MCP.
>
> **Stretch:** Add a second task that asks for extra memory *just for itself* via a
> resource override, while the others stay small — then find in the UI where it shows the
> different request. Ask the MCP the right way to override resources for one task. (Reality
> check: your devbox is one `m6i.2xlarge`, 8 vCPU / 32 GB total. Ask for 100 GB and the
> pod sits in `Pending` forever — that's arithmetic, not a bug, and the same arithmetic on
> a 500-node cluster.)

### ✅ Checkpoint

In the Flyte UI, open the execution and find the flaky task. It shows **multiple
attempts** — the early ones failed, the last succeeded — and the **run as a whole
succeeded**. Click into a failed attempt: its logs and error are still there. The failure
isn't swept away, it's recorded, and the run survived it anyway.

### 💡 Understand

Ask Kiro (via the MCP): how do retries let you run on **cheap, interruptible** compute? If
losing a pod cost you the whole eight-hour run you'd buy expensive on-demand; if it costs
one retried task, you buy spot at a fraction of the price. Reliability that's cheap to have
changes what hardware you can afford.

---

## 2. See inside

So far you've watched Flyte's *operational* view — what ran, how long, what failed. It
stops at the container boundary. It can't tell you your parse quality fell off a cliff on
scanned pages, or which prompt variant won. For that you'd normally dump a CSV, open a
notebook, make a chart, and watch it drift out of date.

Flyte's alternative: a task emits an **HTML report** attached to the execution, and it
can update **while the task runs** — so a long job isn't a black box you stare at for
forty minutes only to find it went wrong at minute three.

> **Your task:** Create `work/report.py` with a task that generates an interactive HTML
> report — a chart or small dashboard over data it computes — and updates it live as it
> works. You should be able to open the report tab on the execution *while it's still
> running* and watch it fill in.
>
> **Hints:** The `flyte.report` module gives you `log`, `flush`, `replace`, `get_tab`.
> Reporting doesn't happen by accident — there's a flag on the task decorator that turns
> it on; without it, your report code runs and nothing shows in the UI. Ask the MCP how
> reporting is enabled and how to flush progress mid-run. Have the task do iterative work
> and flush after each update.
>
> **Stretch:** Ask Kiro the difference between what the execution view tells you and what a
> report tells you — and when you'd reach for each.

### ✅ Checkpoint

In the Flyte UI, open the execution, find the **report** tab, and watch it update while
the task runs. The chart is rendered, interactive, and attached to *this* run — not a file
someone has to find, not a notebook that only runs on one laptop.

### 💡 Understand

The execution view is **operational** (did it run? how long? what failed? — Flyte knows
this for free). A report is **semantic** (is the output any *good*? — only your code knows
what "good" means). "It succeeded" and "it worked" are different claims; a green execution
with garbage outputs is a pipeline that succeeded at doing the wrong thing. This distinction
comes straight back in [Module 11](11-arize-phoenix.md).

---

## 3. Ship it

Everything so far has been `flyte run` — it uploads your code and runs it *now*. Great for
developing, terrible as a production story: the pipeline exists only as long as your
session does. Close the tab and the recipe is gone.

`flyte deploy` registers your task environment on the backend as a **named, versioned
entity** — something a schedule can fire, another system can trigger, or a colleague can
run without ever seeing your source.

> **Your task:** Deploy the environment from `work/hello.py` (Module 01) so it becomes a
> named entity on the backend. Confirm it registered, find it in the UI *without* going
> through an execution, then trigger it *without* re-running from source.
>
> **Hints:** Ask the MCP the difference between `flyte run` and `flyte deploy`. After
> deploying, the entity should be findable in the UI as a standalone thing, and triggerable
> directly — it's on the backend now, it doesn't need your file.
>
> **Stretch:** Ask Kiro what you can do now that you couldn't before — and how Flyte v2
> versions deployed entities (deploy again and you get a new version, not a silent
> overwrite, so a schedule pinned to a version doesn't change under you).

### ✅ Checkpoint

In the Flyte UI, find your deployed entity **without** opening an execution — it exists on
its own. Then have Kiro trigger it without re-running from source.

---

## Where you've landed

Stack it up: a plain Python function ([01](01-first-task.md)) that fans out across
hundreds of inputs ([02](02-fan-out.md)), survives failure, shows its work live, and now
exists as a durable thing the platform can operate. You never wrote a queue, a retry loop,
a progress tracker, a dashboard, or a scheduler — and you checked each one yourself in the
UI rather than taking anyone's word for it.

---

**Next up — the partner tracks.** Same Flyte, pointed at real problems:

- [10 -- LlamaIndex](10-llamaindex.md): parse a pile of PDFs in parallel, cheaply
- [11 -- Arize Phoenix](11-arize-phoenix.md): see inside an agent, not just around it
