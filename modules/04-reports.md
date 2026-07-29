# 04 -- See inside

**~30 minutes.**

So far you've watched Flyte's view of your pipeline: what ran, how long, what failed.
That's *orchestration* -- real, but it stops at the container boundary. It can't tell you
that your parse quality fell off a cliff on scanned documents, or which prompt variant
won.

For that you'd normally leave: dump a CSV, open a notebook, make a chart, paste it in
Slack, watch it drift out of date immediately.

Flyte's alternative is that a task can emit an **HTML report** that's attached to the
execution and travels with it. The chart lives with the run that produced it, forever.

---

## Build it

Reports in Flyte use the `flyte.report` module -- it provides `log`, `flush`, `replace`,
and `get_tab`. But reporting does not happen automatically. There is a flag on the task
decorator that enables it. If nothing shows up in the UI, that flag is missing.

> **Your task:** Create `work/report.py` with a task that generates an interactive HTML report -- a chart or small dashboard over some data it computes. The report should appear as a tab on the execution in the Flyte UI. Run it and find the report.
>
> **Hints:** You need `flyte.report` and you need a flag on the task decorator that enables reporting. Ask the MCP how reporting works and what must be enabled. Without that flag, your report code runs but nothing appears in the UI.
>
> **Stretch:** Ask Kiro what the difference is between what the Flyte execution view shows you and what a `flyte.report` shows you. When would you reach for each?

> ⚠️ **Reports don't happen by accident.** Reporting has to be switched on for the task
> -- `flyte.report` is a module (`log`, `flush`, `replace`, `get_tab`), and there's a
> flag on the task decorator that enables it. If Kiro writes report code and nothing
> shows up in the UI, that flag is missing. Have it check the MCP rather than guess.

---

## ✅ Checkpoint

In the Flyte UI, open the execution and find the **report** tab.

Your chart is there -- rendered, interactive, attached to this specific run. Not a file
someone has to find. Not a notebook that only runs on one laptop. Part of the execution
record.

---

## Make it live

Now you want the report to update *while* the task runs -- showing progress as work
happens, so a long-running task is not a black box.

> **Your task:** Modify the report task so it does work in a loop and flushes progress to the report as it goes. You should be able to open the report tab while the task is still running and watch it fill in.
>
> **Hints:** Think about `flush` from `flyte.report`. The task needs to do some iterative work (a loop) and call flush after updating the report so the UI reflects current state mid-execution.
>
> **Stretch:** Ask Kiro to explain when a live-updating report saves you from wasting a long pipeline run. What can you catch at minute three that you would otherwise discover at minute forty?

Open the report tab **while it's still running** and watch.

This is the part people don't expect. A long fan-out over ten thousand documents doesn't
have to be a black box you stare at for forty minutes and then discover was wrong at
minute three. The task can show you its work as it happens, and you can kill it early
when you see it go bad.

---

## 💡 Understand what just happened

Ask Kiro (using the Flyte MCP) to explain the difference between what the execution view
tells you and what a `flyte.report` tells you. When would you reach for each?

The distinction is worth being precise about, because it comes back in
[Module 11](11-arize-phoenix.md):

- The **execution view** is *operational*. Did it run? How long? What failed? Flyte
  knows this about every task without being told, because it's the thing running them.
- A **report** is *semantic*. Is the output any good? Flyte has no idea -- only your code
  knows what "good" means for your data. A report is how your code says so.

"It succeeded" and "it worked" are different claims. A green execution with garbage
outputs is a pipeline that succeeded at doing the wrong thing. Reports are how you catch
that.

---

**Next:** [05 -- Deploy it](05-deploy.md)
