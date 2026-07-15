# 05 — Deploy it

**~30 minutes.**

Everything so far has been `flyte run` — which uploads your code from wherever you're
sitting and runs it right now. That's a great development loop and a terrible production
story, because the pipeline only exists as long as your session does. It lives in your
sandbox. Nobody else can trigger it. Nothing can schedule it. If your tab closes, the
recipe is gone.

`flyte deploy` registers your task environment on the backend as a **named, versioned
entity**. It stops being "code I ran once" and becomes something the platform knows
about — that a schedule can fire, that another system can trigger, that a colleague can
run without ever seeing your source.

---

## Build it

You need to move from `flyte run` (ephemeral, tied to your session) to `flyte deploy`
(durable, registered on the backend). This is the difference between a development
artifact and a production one.

> **Your task:** Deploy the environment from `work/hello.py` so it becomes a named entity on the backend. Confirm it registered, find it in the UI without going through an execution, and then trigger it without re-running from source.
>
> **Hints:** There is a difference between `flyte run` and `flyte deploy`. Ask the MCP to explain it. After deploying, the entity should be findable in the UI as a standalone thing -- not just as part of an execution history. You should be able to trigger the deployed entity directly.
>
> **Stretch:** Ask Kiro what you can do now that the entity is deployed that you could not do before. What would it take to run this on a schedule or trigger it from another system?

---

## ✅ Checkpoint

In the Flyte UI, find your deployed task or environment **without going through an
execution**. It's listed as a thing that exists on its own.

Now the real test: ask Kiro to trigger the deployed entity **without re-running from
source**. It's on the backend now. It doesn't need your file anymore.

---

## 💡 Understand what just happened

Ask Kiro (using the Flyte MCP): now that it is deployed, what can you do that you could
not before? What would it take to run this on a schedule, or trigger it from another
system?

This is where the arc lands. Look at what you've stacked up:

- A plain Python function ([01](01-first-task.md))
- …that fans out across hundreds of inputs ([02](02-fan-out.md))
- …survives failures and sizes its own compute ([03](03-resilience.md))
- …shows its work while it runs ([04](04-reports.md))
- …and now exists as a durable thing the platform can operate

You never wrote a queue, a retry loop, a progress tracker, a dashboard, or a scheduler.
That's the pitch, and you just checked it yourself rather than taking anyone's word for
it.

---

## Worth knowing

Deployment is where versioning starts to matter — deploy again and you get a new version
rather than a silent overwrite, so a schedule pinned to a version doesn't change under
you because someone pushed at 4pm on a Friday. Ask Kiro (and the MCP) how Flyte v2
versions deployed entities if you want to pull that thread.

---

**Next up — the partner tracks.** Same Flyte you've been using, pointed at real problems:

- [10 — LlamaIndex](10-llamaindex.md): parse a pile of PDFs in parallel, cheaply
- [11 — Arize Phoenix](11-arize-phoenix.md): see inside an agent, not just around it
