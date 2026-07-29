# 03 -- Survive failure

**~30 minutes.**

Real pipelines fail. A model API rate-limits you, a spot instance disappears, S3 has a
bad minute, one PDF in ten thousand is malformed. None of that is exceptional -- at scale
it's Tuesday.

The question isn't how to prevent it. It's whether a transient blip costs you the whole
run.

---

## Retries

You need to build a task that fails on purpose and then survives via retries. The key
challenge: every retry runs in a **fresh pod** with fresh memory and a fresh filesystem.
A naive counter variable resets to zero on every attempt. The task has to read its
attempt number from what Flyte provides.

> **Your task:** Create `work/resilient.py` with a task that deliberately fails on its first attempt and succeeds when retried. The task must detect its current attempt number from Flyte (not from a local variable) and use that to decide whether to fail. Configure retries so the run recovers. Run it and confirm the final status.
>
> **Hints:** Each retry is a new pod -- local state does not survive. Ask the MCP how a task reads its current attempt number. Also ask where `retries` goes in Flyte v2 -- it is NOT on the `TaskEnvironment`.
>
> **Stretch:** Ask Kiro to explain why a counter variable (`attempts += 1`) would not work for detecting retry attempts. What does a "fresh pod" really mean?

> ℹ️ **The trick worth understanding.** Your first instinct is a counter -- `attempts +=
> 1`. It won't work. **Every retry is a brand-new pod**: fresh process, fresh memory,
> fresh filesystem. Your counter resets to zero and the task fails forever, identically,
> looking for all the world like retries are broken.
>
> The task has to read the attempt number that Flyte *hands* it. This is the shape of
> every distributed-retry bug you'll ever write, and it's much cheaper to learn here
> than at 2am.

> ⚠️ **`retries` is not a `TaskEnvironment` parameter.** It goes on `@env.task(retries=3)`
> or `task.override(retries=3)`. This is the single most common Flyte v2 mistake, and
> models make it constantly because v1 worked differently. If Kiro puts `retries` on the
> `TaskEnvironment`, it's guessing -- point it back at the MCP.

### ✅ Checkpoint

In the Flyte UI, open the execution and find the flaky task. It shows **multiple
attempts**, the early ones failed, the last one succeeded -- and the **run as a whole
succeeded**.

Click into the failed attempt. Its logs and error are still there. That's the point:
the failure isn't swept away, it's recorded, and the run survived it anyway.

---

## Resources

Retries handle *transient* failure. The other kind is a task that simply needs more
machine than its neighbours -- one memory-hungry step in a pipeline of cheap ones.

The wasteful fix is to raise memory everywhere and pay for it on every task. The good
fix is to let one task ask for more, just for itself.

> **Your task:** Add a second task to `work/resilient.py` that requests extra memory just for itself via a resource override, while other tasks stay small. Run it, then find in the UI where you can confirm it received different resources than its neighbours.
>
> **Hints:** Ask the MCP for the right way to override resources for a single task in Flyte v2. Think about `task.override()` or the task decorator. The UI shows requested resources per task.
>
> **Stretch:** Ask Kiro when you would override resources for one task instead of raising them for the whole environment. What is the cost tradeoff?

### ✅ Checkpoint

In the UI, find the task and confirm its requested resources differ from its neighbours'.

> **Reality check:** your devbox is one `m6i.2xlarge` -- 8 vCPU and 32 GB, total. Ask for
> 100 GB and the pod will sit in `Pending` forever, because nothing can schedule it.
> That's not a bug, it's arithmetic, and it's the same arithmetic on a 500-node cluster --
> just with more room before it bites. If a task hangs in `Pending`, this is your first
> suspect.

---

## 💡 Understand what just happened

Ask Kiro to explain briefly: how do retries and per-task resource overrides help you run
cheaply *and* reliably? When would you override resources for one task instead of raising
them for everything? Have it use the Flyte MCP.

The economic argument, so you can grade the answer:

Retries let you run on **cheap, interruptible compute**. If losing a pod costs you the
whole eight-hour run, you buy on-demand and pay a large premium for reliability you're
extracting from your wallet instead of your orchestrator. If losing a pod costs you one
retried task, you buy spot at a fraction of the price. Reliability that's cheap to have
changes what hardware you can afford to use.

Per-task resources are the same argument in the other direction: one task needing 32 GB
shouldn't set the price for the two hundred that need 500 MB.

---

**Next:** [04 -- See inside](04-reports.md)
