# 02 — Fan out

**~30 minutes.**

You rarely run one thing. You run the same thing across a thousand things — every PDF,
every customer, every prompt variant, every checkpoint in a sweep.

In plain Python that's a `for` loop, and a `for` loop has a specific set of problems: it
runs one at a time, one bad input kills the whole run, and while it's going you have no
idea where it is. Every team eventually rebuilds the same scaffolding — a work queue,
retry logic, progress tracking, partial-failure handling — to escape those problems.

Flyte's answer is `flyte.map`, and the interesting part isn't the parallelism. It's that
each input becomes **its own tracked, retryable unit**.

---

## Build it

**Prompt Kiro:**

> Using the Flyte MCP, add a task to `work/hello.py` that uses `flyte.map` to run my
> greeting task across a list of at least 20 names, in parallel, returning all the
> greetings. Confirm the exact `flyte.map` signature with the MCP first. Then run it and
> give me the execution URL.

---

## ✅ Checkpoint

**In the Flyte UI**, open the execution.

You should see **one child action per name** — twenty of them — not a single task
looping twenty times. Look at their start times: they overlap. That's real parallelism
across real pods, not threads.

Click into one. It has its own inputs, its own outputs, its own logs, its own status.
It can be retried on its own. **That's the thing to notice.** Not "it went faster" —
"each one is independently real."

---

## 💡 Understand what just happened

**Prompt Kiro:**

> Using the Flyte MCP, explain why `flyte.map` is better here than a plain Python `for`
> loop. What do I get — scaling, retries, visibility — that the loop wouldn't give me?

The answer to listen for: in a loop, one exception loses everything, and you learn about
it at the end. With `map`, input #14 failing is *input #14 failing* — it retries on its
own, and the other nineteen neither know nor care. You can see exactly which one broke,
why, and re-run just that one.

That's the difference between a script and a pipeline.

---

## Now make it bigger

**Prompt Kiro:**

> Now fan it out across 200 inputs, but limit how many run at once. Ask the MCP how to
> set concurrency on `flyte.map`.

Watch the UI as it runs. You'll see actions moving through states in waves as slots free
up.

**Why cap it?** Because 200 pods that all hit the same rate-limited API at once will get
you a face full of `429`s — which is exactly what happens in [Module 10](10-llamaindex.md)
when the thing you're fanning out over is a metered cloud API. Concurrency control is how
you match your fan-out to what's downstream of it. Worth knowing before you need it.

---

## 💡 The part worth remembering

Your greeting task didn't change. Not one line.

You made it run twenty times in parallel, then two hundred times with a concurrency cap,
by changing *how it's called* — never *what it does*. The task stayed a plain function.

That separation — business logic in the function, execution strategy outside it — is
most of the value on offer here. It's why the same task can run once on your laptop and
ten thousand times on a cluster without anyone rewriting it.

---

**Next:** [03 — Survive failure](03-resilience.md)
