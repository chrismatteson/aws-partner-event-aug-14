# 04 — See inside

**~30 minutes.**

So far you've watched Flyte's view of your pipeline: what ran, how long, what failed.
That's *orchestration* — real, but it stops at the container boundary. It can't tell you
that your parse quality fell off a cliff on scanned documents, or which prompt variant
won.

For that you'd normally leave: dump a CSV, open a notebook, make a chart, paste it in
Slack, watch it drift out of date immediately.

Flyte's alternative is that a task can emit an **HTML report** that's attached to the
execution and travels with it. The chart lives with the run that produced it, forever.

---

## Build it

**Prompt Kiro:**

> Using the Flyte MCP, create `work/report.py` with a task that generates an interactive
> HTML report using `flyte.report` — a chart or a small dashboard over some data it
> computes. Ask the MCP how `flyte.report` works and what has to be enabled on the task
> for reporting to happen. Then run it and tell me where to find the report in the UI.

> ⚠️ **Reports don't happen by accident.** Reporting has to be switched on for the task
> — `flyte.report` is a module (`log`, `flush`, `replace`, `get_tab`), and there's a
> flag on the task decorator that enables it. If Kiro writes report code and nothing
> shows up in the UI, that flag is missing. Have it check the MCP rather than guess.

---

## ✅ Checkpoint

In the Flyte UI, open the execution and find the **report** tab.

Your chart is there — rendered, interactive, attached to this specific run. Not a file
someone has to find. Not a notebook that only runs on one laptop. Part of the execution
record.

---

## Make it live

**Prompt Kiro:**

> Now make the report update *while* the task runs — do some work in a loop and flush
> progress to the report as it goes, so I can watch it fill in.

Open the report tab **while it's still running** and watch.

This is the part people don't expect. A long fan-out over ten thousand documents doesn't
have to be a black box you stare at for forty minutes and then discover was wrong at
minute three. The task can show you its work as it happens, and you can kill it early
when you see it go bad.

---

## 💡 Understand what just happened

**Prompt Kiro:**

> Using the Flyte MCP: what's the difference between what the Flyte execution view tells
> me and what a `flyte.report` tells me? When would I reach for each?

The distinction is worth being precise about, because it comes back in
[Module 11](11-arize-phoenix.md):

- The **execution view** is *operational*. Did it run? How long? What failed? Flyte
  knows this about every task without being told, because it's the thing running them.
- A **report** is *semantic*. Is the output any good? Flyte has no idea — only your code
  knows what "good" means for your data. A report is how your code says so.

"It succeeded" and "it worked" are different claims. A green execution with garbage
outputs is a pipeline that succeeded at doing the wrong thing. Reports are how you catch
that.

---

**Next:** [05 — Deploy it](05-deploy.md)
