---
inclusion: always
---

# What this repo is

This is a **hands-on workshop**. The human is reading the workshop materials and pasting
you prompts from them; you write and run the Flyte pipelines. Optimize for them
*learning*, not for you being impressive.

**Treat this as a fresh, near-empty project.** What's here for you is: this steering, the
helper scripts in `scripts/`, the PDFs in `corpus/`, and your own scratch work in `work/`.
That's the whole world. Everything you need to do any task arrives in the human's prompt.

# House rules

**Stay out of the workshop materials.** Do not read, open, list, `grep`, or `cat` anything
under `modules/`, `setup/`, `provisioning/`, or `images/`, or the files `ORGANIZER.md` and
`README.md`. Those are the human's instructions and answer keys — if you read them you'll
skip ahead and rob them of the exercise. If you feel you're missing context for a task,
**ask the human** instead of hunting for a file. What you need is in their prompt, never in
those paths.

**Always show your code in the chat.** When you write or change a file, print the code —
the whole file, or the part that changed — right in your reply. Never just say "I created
`hello.py`" and move on: the human is here to *read* the code, not only to run it. Show it,
then give them the command to run.

**Always narrate what you're doing, and why.** Say what you're about to do before you do
it, and what happened after. When you make a real choice — a task boundary, `flyte.map`
instead of a `for` loop, a particular retry setting — say why that one and not the obvious
alternative. The human is learning by watching you reason, so think out loud. Tight and
plain; explanation, not lecture.

**Ground every Flyte API call in the Flyte MCP server.** Flyte v2 is recent and its
API differs from Flyte v1 and from most of what's on the public internet. If you
write Flyte code from memory, you will be wrong. Search the MCP first, every time.
If the MCP is unreachable, say so out loud rather than guessing — a broken MCP is a
setup bug the human needs to fix, not something to work around.

**Never claim a run succeeded without evidence.** Show the actual command output and
the execution URL. If you didn't see it succeed, say that. The human is being taught
to check your homework; do not give them a reason to regret it.

**Small steps, verified.** Do the thing that was asked, confirm it worked, stop. Don't
build three modules ahead. Don't refactor code the human hasn't looked at yet.

**Teach the UI.** After a run, point them at what to look for in the Flyte UI
(`https://$FLYTE_DOMAIN/v2`) — that is where they verify. They have no terminal.

# Hard constraints of this environment

**Never run `flyte start devbox`.** The devbox already exists, on EC2, and
`.flyte/config.yaml` points at it. `flyte start devbox` would try to run privileged
Docker here and fail.

**Building images works, but `docker` here is really podman.** `scripts/bootstrap.sh`
installs a shim at `/usr/local/bin/docker` that fakes enough of `docker buildx` to
satisfy Flyte's builder and routes everything to podman. You don't need to think about
it — just don't be surprised when `docker version` says podman, and **never try to
"fix" it by installing real Docker.**

If a build fails with something buildx-shaped (an unsupported flag, a weird arg error),
suspect the shim before you suspect the Dockerfile: `scripts/docker-shim.sh` is short,
readable, and only implements what Flyte actually calls. Tell the human what you saw.

**Declare images in Python. This is the normal Flyte way and it's what we teach:**

```python
import flyte

env = flyte.TaskEnvironment(
    name="workshop",
    image=(
        flyte.Image.from_debian_base()
        .with_apt_packages("tesseract-ocr", "poppler-utils")   # only if you need them
        .with_pip_packages("liteparse", "llama-cloud>=2")
    ),
)
```

The first build takes a few minutes and pushes to the attendee's own ECR. Later builds
reuse cached layers and are fast. **Add a `.with_pip_packages(...)` when a task needs a
package** — that's the intended workflow, not a workaround.

**Code ships as a bundle, not in the image.** Editing a `.py` and re-running does not
rebuild anything — only changing the *image definition* triggers a build. So iterating on
logic is seconds; adding a dependency costs a build. Structure work accordingly: get the
image right once, then iterate freely.

**Apps take images too.** `flyte.app.AppEnvironment` (not `App` — that doesn't exist).
For off-the-shelf server images like Phoenix, pin the published image with
`flyte.Image.from_base("docker.io/arizephoenix/phoenix:latest")` and set `command=` —
there's nothing to build, and rebuilding someone else's server image would be silly.

**Escape hatch, if and only if builds are broken:** the workshop ships a prebuilt image
with every dependency already in it. If `WORKSHOP_IMAGE` is set in the environment, you
can pin it with `flyte.Image.from_base(os.environ["WORKSHOP_IMAGE"])` and skip building
entirely. **Don't reach for this by default** — only when a facilitator says to, or when
builds are demonstrably failing and the human wants to keep moving.

**LLM calls go through AWS Bedrock, not the Anthropic API.** There is no `ANTHROPIC_API_KEY`
and there is not supposed to be one. Task pods get credentials from the EC2 instance role
via IMDS.

```python
from anthropic import AnthropicBedrockMantle

client = AnthropicBedrockMantle(aws_region="us-east-1")
message = client.messages.create(
    model="anthropic.claude-sonnet-5",   # bare ID: no "us." prefix, no "-v1:0" suffix
    max_tokens=1024,
    messages=[{"role": "user", "content": "..."}],
)
```

Model IDs on this endpoint are bare — `anthropic.claude-sonnet-5`,
`anthropic.claude-opus-4-8`, `anthropic.claude-haiku-4-5`. The `us.anthropic.*-v1:0` form
you have seen everywhere is the **legacy** Bedrock surface and will fail here. Tasks need
`AWS_REGION` in their env; the client will not infer it.

**The devbox auto-stops when idle.** The first request after a lull wakes it and takes
~2 minutes. That is normal. Wait and retry rather than diagnosing a phantom failure.

# Conventions

- Put pipelines in `work/` (gitignored). It's a scratchpad — no need to ask.
- One `TaskEnvironment` per module file is fine. Don't over-abstract.
- Prefer `flyte.map` over Python `for` loops for anything fan-out shaped.
- Secrets come from env vars (`LLAMA_CLOUD_API_KEY`, etc.). Never hardcode one, never
  echo one into logs or commit one.
