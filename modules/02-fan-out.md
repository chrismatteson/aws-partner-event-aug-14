# 02 -- Fan out

**~30 minutes.**

You rarely run one thing. You run the same thing across a thousand things -- every PDF,
every customer, every prompt variant, every checkpoint in a sweep.

In plain Python that's a `for` loop, and a `for` loop has a specific set of problems: it
runs one at a time, one bad input kills the whole run, and while it's going you have no
idea where it is. Every team eventually rebuilds the same scaffolding -- a work queue,
retry logic, progress tracking, partial-failure handling -- to escape those problems.

Flyte's answer is `flyte.map`, and the interesting part isn't the parallelism. It's that
each input becomes **its own tracked, retryable unit**.

---

## Build it

You already have a greeting task from Module 01. Now you need to run it across many
inputs at once. In Flyte v2, `flyte.map` takes a task and a list of inputs and fans them
out -- each one becomes its own tracked action with its own inputs, outputs, logs, and
retry lifecycle.

> **Your task:** Make your greeting task from `work/hello.py` run across at least 20 names in parallel using `flyte.map`, returning all the greetings. Run it and get the execution URL.
>
> **Hints:** You need the `flyte.map` function. Have Kiro confirm the exact signature with the MCP -- it takes a task and a list. The key insight is that each input becomes its own independently tracked unit, not just a loop iteration.
>
> **Stretch:** Ask Kiro to explain why `flyte.map` is better than a plain Python `for` loop. What do you get -- scaling, retries, visibility -- that the loop would not give you?

---

## ✅ Checkpoint

**In the Flyte UI**, open the execution.

You should see **one child action per name** -- twenty of them -- not a single task
looping twenty times. Look at their start times: they overlap. That's real parallelism
across real pods, not threads.

Click into one. It has its own inputs, its own outputs, its own logs, its own status.
It can be retried on its own. **That's the thing to notice.** Not "it went faster" --
"each one is independently real."

---

## 💡 Understand what just happened

Ask Kiro to explain (using the Flyte MCP) what makes `flyte.map` different from
running a task in a loop. What happens when input #14 fails? How does that compare to
a `for` loop where input #14 throws an exception?

The answer to listen for: in a loop, one exception loses everything, and you learn about
it at the end. With `map`, input #14 failing is *input #14 failing* -- it retries on its
own, and the other nineteen neither know nor care. You can see exactly which one broke,
why, and re-run just that one.

That's the difference between a script and a pipeline.

---

## Now make it bigger

Now you need to scale up and learn about concurrency control. When you fan out across
hundreds of inputs that all hit the same downstream resource, you need to limit how many
run at once -- otherwise you get a wall of rate-limit errors.

> **Your task:** Fan the greeting task out across 200 inputs, but cap how many run concurrently. Watch the UI as actions move through states in waves.
>
> **Hints:** Ask the MCP how to set concurrency on `flyte.map`. There is a parameter that limits how many map actions can execute at the same time.
>
> **Stretch:** Ask Kiro why concurrency caps matter when fanning out over a rate-limited API. What happens in [Module 10](10-llamaindex.md) without one?

**Why cap it?** Because 200 pods that all hit the same rate-limited API at once will get
you a face full of `429`s -- which is exactly what happens in [Module 10](10-llamaindex.md)
when the thing you're fanning out over is a metered cloud API. Concurrency control is how
you match your fan-out to what's downstream of it. Worth knowing before you need it.

---

## 💡 The part worth remembering

Your greeting task didn't change. Not one line.

You made it run twenty times in parallel, then two hundred times with a concurrency cap,
by changing *how it's called* -- never *what it does*. The task stayed a plain function.

That separation -- business logic in the function, execution strategy outside it -- is
most of the value on offer here. It's why the same task can run once on your laptop and
ten thousand times on a cluster without anyone rewriting it.

---

**Next:** [03 -- Survive, see, and ship](03-resilience.md)
