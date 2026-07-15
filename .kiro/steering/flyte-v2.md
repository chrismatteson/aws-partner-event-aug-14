---
inclusion: always
---

# Flyte v2 — orientation, not a reference

**The Flyte MCP server is the source of truth for every signature.** This file exists
so you know *what to ask it* and which mistakes to avoid. It is deliberately not an
API reference — if you need an exact signature, search the MCP.

## The single biggest failure mode

**Flyte v2 is not Flyte v1, and most Flyte code on the public internet is v1.** If you
pattern-match on training data you will write `@workflow`, `@task`, `flytekit`,
`FlyteRemote`, `pyflyte`, `LaunchPlan`, `dynamic`, `map_task`, `Resources(mem=...)` —
**none of which are how v2 works.** Every one of those is a v1 API.

v2 is the `flyte` package (not `flytekit`), the `flyte` CLI (not `pyflyte`).
If you catch yourself importing `flytekit`, stop and search the MCP.

## Shape of a v2 program

```python
import os
import flyte

env = flyte.TaskEnvironment(
    name="workshop",
    image=flyte.Image.from_debian_base().with_pip_packages("pandas"),
)

@env.task
async def greet(name: str) -> str:
    return f"Hello, {name}!"

@env.task
async def main(names: list[str]) -> list[str]:
    return [r async for r in flyte.map(greet, names)]
```

- Tasks are `async def`. A task calls another task by awaiting it — that's the graph.
  There is no separate `@workflow` decorator; a task that calls tasks *is* the workflow.
- A task's fully-qualified name is `<env_name>.<function_name>` — so `main` above is
  `workshop.main`. That's what you pass to `flyte run`.
- Confirm `flyte.map`'s exact signature with the MCP before using it.

## The gotcha that wastes the most time

**Some settings only exist at one level.** Getting this wrong produces confusing
`TypeError`s. The real table (from the SDK docstring):

| Setting | `TaskEnvironment(...)` | `@env.task(...)` | `.override(...)` |
|---|:--:|:--:|:--:|
| `name`, `image` | ✅ | — | — |
| `resources`, `env_vars`, `secrets` | ✅ | — | ✅ |
| `cache`, `pod_template`, `interruptible` | ✅ | ✅ | ✅ |
| **`retries`, `timeout`** | **—** | ✅ | ✅ |
| `report` | — | ✅ | — |

**`retries` and `timeout` are NOT `TaskEnvironment` parameters.** They go on
`@env.task(retries=3)` or `task.override(retries=3)`. This is the one people get wrong.

Also: `cache` defaults to `"disable"`. If you want caching, ask for it.

## Things worth knowing

- `flyte.Resources(cpu=1, memory="1Gi", gpu="T4:1", disk="10Gi")` — `cpu` and `memory`
  take ranges too: `cpu=(1, 2)`.
- `flyte.RetryStrategy(count=5, backoff=flyte.Backoff(...))` for paced retries;
  plain `retries=5` retries back-to-back with no delay.
- `flyte.report` is a module — `flyte.report.log()`, `.flush()`, `.replace()`,
  `.get_tab()`, `.current_report()`. Reports need `@env.task(report=True)`.
- **Every retry is a brand-new pod.** In-process counters and local files do not
  survive a retry. To know which attempt you're on, read it from the run context
  (`flyte.ctx()`) — ask the MCP for the exact attribute.
- Useful top-level names: `init`, `init_from_config`, `run`, `deploy`, `map`, `trace`,
  `group`, `with_runcontext`, `ctx`, `Cache`, `Secret`, `Timeout`, `ReusePolicy`.

## Running things

`flyte run <file.py> <task_name> --arg value` — this uploads a **code bundle** to the
cluster; it does not rebuild an image. Iteration is seconds, not minutes.

The config at `.flyte/config.yaml` points at this attendee's devbox and authenticates
via Cognito (`authType: ExternalCommand`). Don't regenerate it, don't "fix" it, and
don't switch it to `pkce` — there's no browser in this sandbox for PKCE to open.
If auth looks broken, the token script is `scripts/flyte-token.sh`; run it and read
the error rather than rewriting the config.
