# 99 -- Now you drive

**~60 minutes.** No task boxes, no hints, no scaffolding. That's the point.

You've seen the whole arc: cloud execution, fan-out, resilience, reports, deployment,
and two partner integrations on top. You know the loop -- **ask Kiro to build it, run it,
then go prove from the execution that it actually worked.**

Time to fish on your own.

---

## Pick something

Any of these. Or ignore all of them and build the thing you actually came here with --
that's the better option if you have one.

**Go wider**
- Fan the PDF pipeline from [Module 10](10-llamaindex.md) out over 500 documents with a
  concurrency cap. Find where it breaks. Something will.
- Run an eval sweep: one prompt variant per task, `flyte.map` over the grid, results in
  a `flyte.report` chart. Now you have an eval harness.

**Go deeper**
- Build a multi-step pipeline where one task's output feeds the next, and the steps that
  *can* run in parallel do.
- Add caching to an expensive step, then prove from the UI that the second run skipped it.
- Chain both partner tracks: parse PDFs with LlamaIndex, run an agent over them, trace it
  in Phoenix, chart the results in a report. That's a real system.

**Go sideways**
- Take something from your own work -- a nightly script, a batch job, a notebook cell you
  keep re-running -- and make it a Flyte pipeline. Run it. Deploy it.
- Give a task a GPU and prove from the UI it got one. (Your devbox may not have one. Find
  out what happens, and why the pod's status tells you exactly what went wrong.)
- Build a token-budget guard: an agent task that hard-stops when it burns past a limit.
  Enforcement living in the orchestrator, where the agent actually runs -- not a dashboard
  watching from outside.

---

## The habits worth keeping

**Make Kiro use the MCP.** Every time it writes Flyte from memory, it writes v1 -- and v1
has been wrong for a while. `@workflow`, `flytekit`, `pyflyte`, `map_task`: all tells.
Ground it or it drifts.

**Never take "it worked" on faith.** You have a UI. Use it. This is the habit that
generalizes furthest past today -- you'll be reviewing agent output for the rest of your
career, and "go look at the actual artifact" is the whole skill.

**Ask why, not just what.** "Explain what you just built and why that approach" is how
this stops being a demo you watched and starts being something you know.

---

## Before you go

Everything you did today lived in one Kiro session, and **that session -- and your whole
AWS account -- gets torn down after the event.** So if you built something you want to
keep, get it out now.

Your scratch code is in `work/`, which is gitignored so it stayed out of your way all day.
That means a normal PR won't include it. To keep something, tell Kiro exactly what:

> Open a pull request to my fork that force-adds `work/the_file_i_want.py` (it's
> gitignored -- use `git add -f`), so I don't lose it when this session ends.

Grab it before you close the tab; there's no getting it back afterward.

## Taking it home

- **Your own devbox:** [unionai-oss/flyte-aws-marketplace](https://github.com/unionai-oss/flyte-aws-marketplace)
  -- the same stack you used today, one CloudFormation deploy. Auto-stops when idle;
  ~$10-80/month depending on mode and use.
- **Examples:** https://github.com/flyteorg/flyte-sdk/tree/main/examples
- **Docs:** https://www.union.ai/docs/v2/flyte/
- **Slack:** https://slack.flyte.org/ -- genuinely responsive, come say what you built.

Thanks for spending the day with us. 🎉
