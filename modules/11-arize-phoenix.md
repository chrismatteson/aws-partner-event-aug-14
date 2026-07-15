# 11 — Arize Phoenix: trace an agent running inside Flyte

**75 minutes.** You'll add a third tab — and you'll deploy the thing behind it yourself.

By now you've watched a lot of work run in the Flyte UI. You know when a task started,
whether it retried, how long it took, and what it returned. That's orchestration, and
it's most of what you need — right up until the thing inside the task is an LLM.

Then the questions change. The task went green in 8 seconds. Fine. But *what did you
actually send to the model?* How many tokens did it burn? The agent called three tools;
which one gave it the answer, and which one wasted a round trip? Why did this run cost
nine cents and the identical one next to it cost two? Flyte can't tell you any of that,
and it shouldn't try. From Flyte's point of view your task is a black box that exited 0.

**Arize Phoenix** opens the box. It's an LLM observability tool built on OpenTelemetry:
your code emits *spans* — one per model call, one per tool call, nested to match the
shape of the agent — and Phoenix renders them as a tree you can click through, with the
full prompt, the full completion, token counts, and latency on every node.

Here's what makes this module different from every Phoenix tutorial you'll find:
**you're going to run Phoenix on your own devbox, as a Flyte app.** Not a hosted account,
not a container on your laptop. One `flyte deploy`, and Phoenix is a live web service on
the same cluster your tasks run on. Your traces never leave your AWS account. There's no
signup, no API key, and no quota to burn.

The point of the module isn't "here's another dashboard." It's this: **Flyte and Phoenix
answer different questions, and you want both.** Flyte tells you *the run* happened —
retries, parallelism, resources, lineage. Phoenix tells you *what the model did* inside
it. By the end you'll have both open, showing you the same executions from two angles,
joined by an ID you stamped yourself.

You'll also collect three separate ways to end up staring at an empty Phoenix with no
error message anywhere. They rhyme, and the pattern they form is the real lesson here.

> **A note on Phoenix and licensing.** Phoenix is the open-source project; Arize AX is
> the commercial platform around it. Phoenix ships under the **Elastic License 2.0**,
> which is *not* OSI-approved — you can use it internally as much as you like, but you
> can't turn around and offer it as a hosted service. Running it on your own cluster for
> your own team, which is exactly what you're about to do, is squarely fine. But if your
> org has a policy that only permits OSI-approved licenses, find out now rather than
> after you've built on it.

---

## 1. Deploy Phoenix onto your own cluster

In Module 05 you learned `flyte deploy` — it took a task and made it a named, reusable
entity on the backend. Hold that thought, because **the same verb ships a whole web
service.** Flyte v2 has a second kind of environment: a `TaskEnvironment` describes work
that runs and exits, and an `AppEnvironment` describes a long-running service that sits
there and answers requests. Underneath it's Knative Serving, which is enabled on your
devbox by default. Nothing to install, nothing to turn on.

So Phoenix — a normal container that serves a web UI and an OTLP receiver — is just an
app you deploy. Same cluster as your tasks. Same `flyte` CLI. One command.

Fair warning: this is new ground. There's no reference repo to copy and no blog post to
follow. The config below was tested on a real devbox and it works, but treat it as a
starting point and confirm the API details against the Flyte MCP.

> Create `work/phoenix_app.py` that deploys Phoenix as a Flyte app. Use this config as
> your starting point, and check `flyte.app` in the Flyte MCP before you run anything:
>
> ```python
> import flyte, flyte.app
>
> phoenix = flyte.app.AppEnvironment(
>     name="phoenix",
>     image="docker.io/arizephoenix/phoenix:latest",
>     port=6006,
>     command=["/usr/bin/python3.13", "-m", "phoenix.server.main", "serve"],
>     requires_auth=False,
>     scaling=flyte.app.Scaling(replicas=(1, 1)),
>     resources=flyte.Resources(cpu="1", memory="2Gi"),
>     env_vars={"PHOENIX_WORKING_DIR": "/tmp/phoenix"},
> )
> ```
>
> Two things I want you to leave exactly as they are, because both are load-bearing: the
> explicit `command` (the Phoenix image is distroless — there is no `/bin/sh` in it, so a
> shell-form command CrashLoops), and `replicas=(1, 1)` (the default scales to zero and
> takes my traces with it).
>
> Deploy it with `flyte deploy work/phoenix_app.py phoenix`. Then find me the app's public
> URL — check the Flyte UI or ask the MCP how apps are addressed on this devbox. Don't
> guess a URL pattern; get me the real one.

### ✅ Checkpoint 1: Phoenix is running on your devbox

- **Flyte UI** (`https://$FLYTE_DOMAIN/v2`): the `phoenix` app is listed and healthy, with
  one replica up.
- **Phoenix UI**: open the URL Kiro found for you. You get the Phoenix interface, with an
  empty project list. Leave this tab open — it's your third tab for the rest of the day.

Sit with that for a second. You just deployed a real web service — a database, an HTTP
server, a whole frontend — onto a Kubernetes cluster, from a browser, without writing a
Dockerfile, a `kubectl` command, a line of YAML, or touching a terminal. It's the same
`flyte deploy` you used in Module 05 on a task. The unit changed; the workflow didn't.

Note what you *didn't* do here: build anything. Phoenix already publishes an image, so we
pinned it with `from_base` and moved on. That's the rule of thumb — **build when the image
is yours, pin when it's someone else's.**

### 💡 Understand what just happened

**`AppEnvironment` is the sibling of `TaskEnvironment`.** One describes work that runs to
completion and dies; the other describes a service that stays up. They both take an image,
resources, and env vars, and they both deploy with `flyte deploy`. The other names in
`flyte.app` sketch the rest of the surface: `AppEndpoint`, `Scaling`, `Port`, `Timeouts`,
`Domain`, `Link`, `Parameter`, `RunOutput`, `ConnectorEnvironment`, `ctx`,
`get_parameter`.

It is `AppEnvironment`, by the way. **`flyte.app.App` does not exist** — it's a natural
thing for an agent to invent, and if Kiro reached for it, that's the MCP not being
consulted. Same reflex as `@workflow` and `map_task`: plausible, confident, wrong.

And note this is not a paid feature you're getting a taste of. Apps are on by default on
the OSS devbox (`internalApps.enabled: true`). What you just did, you can do at home.

> ⚠️ **The distroless trap.** The Phoenix image has no shell. Not a minimal shell — none.
> So the instinctive `command=["/bin/sh", "-c", "phoenix serve"]` doesn't produce a helpful
> error; it produces a CrashLoopBackOff and a container that never starts. That's why the
> command is the explicit interpreter path plus the module. Distroless images are
> increasingly common — smaller, and a much smaller attack surface — and this failure will
> look familiar the second time you hit it.

> 🔴 **The scale-to-zero footgun. This is the one that will get you.** `Scaling` defaults
> to `replicas=(0, 1)` — scale to zero when idle, which is exactly what you want for a
> service nobody's using. But Phoenix's storage here is **ephemeral**: SQLite on the
> container filesystem, no persistent volume. So the sequence is: you deploy Phoenix, you
> go to lunch, Knative scales it to zero, the container is destroyed, and **every trace you
> collected this morning is gone.** No error. No warning. You come back to an empty UI,
> reasonably conclude your instrumentation broke, and spend an hour debugging the wrong
> thing. Pinning `replicas=(1, 1)` keeps the pod alive and your traces with it.
>
> Be honest with yourself about what that buys, though: your traces survive *the day*, not
> the pod. Delete the app, restart the node, and they're gone anyway. That's fine for a
> workshop and wrong for production, where the fix is to point Phoenix at a real database
> with `PHOENIX_SQL_DATABASE_URL` (Postgres) and then let it scale however you like.
> Ephemeral storage is a workshop convenience, not a pattern to copy.

**On auth:** we set `requires_auth=False`, which should make you twitch given how carefully
setup treated Cognito. Here's why it isn't a hole. Your task pods reach Phoenix over
*in-cluster* DNS — pod to Kourier, entirely inside the cluster. That traffic never touches
the ALB and never sees Cognito, so app-level auth would do nothing for it except break
your exporter. The public URL is a different path and still sits behind your devbox
ingress. Nothing here is on the open internet.

---

## 2. One LLM call, from a pod on your cluster

Small first step, and a genuinely interesting one. You're going to make a single Claude
call from inside a Flyte task and watch the span appear in the Phoenix you just deployed.

Think about the path that span takes — it's remarkably short. Your Kiro sandbox uploads a
code bundle to your devbox. The devbox schedules a pod on k3s, on an EC2 instance in *your*
AWS account. That pod calls Claude on Bedrock, and on the way out it ships a span over OTLP
to a Phoenix pod sitting a few hundred microseconds away on the same cluster. Nothing on
your laptop is involved. Nothing in the Kiro sandbox is involved. Nothing leaves your AWS
account at all.

**About the model calls: there are no API keys today.** Your task pods run on EC2 in your
own AWS account, so they pick up credentials from the instance role via IMDS automatically
and call **Bedrock** with them. Nothing to add to your secrets, nothing to rotate, nothing
to leak. The client is `AnthropicBedrockMantle` from the `anthropic` SDK
(`anthropic[bedrock]`, already in the workshop image):

```python
from anthropic import AnthropicBedrockMantle

client = AnthropicBedrockMantle(aws_region="us-east-1")
message = client.messages.create(
    model="anthropic.claude-sonnet-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "..."}],
)
```

> ⚠️ **The model IDs on this endpoint are bare.** `anthropic.claude-sonnet-5`,
> `anthropic.claude-opus-4-8`, `anthropic.claude-haiku-4-5`. **No `us.` prefix. No `-v1:0`
> suffix.** Those belong to the *legacy* Bedrock surface, they are all over the public
> internet, and an agent will reach for them with total confidence — the same trap as the
> stale LlamaIndex SDK in Module 10. If Kiro writes `us.anthropic.claude-sonnet-4-v1:0`,
> that's training data talking, not the docs. Use **Sonnet 5** unless you have a reason not
> to.

Two more ingredients:

- `phoenix.otel.register()` sets up the tracer and points it at your Phoenix.
- `auto_instrument=True` monkey-patches whatever supported client libraries are installed,
  so `anthropic` calls start emitting spans without you touching them.

And the endpoint your tasks export to is **in-cluster DNS**, which looks like this:

```
http://{app-name}-{project}-{domain}.{namespace}.svc.cluster.local/v1/traces
```

For a stock devbox that's
`http://phoenix-flytesnacks-development.flyte.svc.cluster.local/v1/traces` — but confirm
your own project, domain, and namespace rather than trusting mine.

This is also the sane version of a trap you'd hit anywhere else. A pod that resolves
`localhost` gets *itself*, not your machine and not the devbox host — so a collector
endpoint is only ever as good as the address the *pod* can route to. In-cluster DNS is that
address, and it's the reason running Phoenix on the same cluster makes the networking
boring instead of a project.

> ⚠️ **Port 80, not 6006.** Knative maps the service's `:80` onto your container's port, so
> the in-cluster URL has no port in it. Putting `:6006` in that hostname gets you a
> connection refused. The `6006` in the `AppEnvironment` is the *container's* port; these
> are two different layers and it's an easy hour to lose.

> ⚠️ **Use the HTTP exporter, not gRPC.** Knative routes exactly one port per service, so
> Phoenix's OTLP-gRPC on 4317 is simply unreachable here — only the port you declared
> exists. That's fine: port 6006 serves **both** the UI and OTLP-over-HTTP. Pointing
> `PHOENIX_COLLECTOR_ENDPOINT` at the full `/v1/traces` path is what selects the HTTP
> exporter. Have Kiro confirm how `phoenix.otel.register()` chooses its protocol and make
> sure it lands on HTTP — `arize-phoenix-otel` will happily default to gRPC, and gRPC is
> the one thing that cannot work on this deployment.

> Create `work/trace_one.py`. Define a Flyte `TaskEnvironment` named `phoenix1` whose
> image is `flyte.Image.from_debian_base()` with pip packages `arize-phoenix-otel`,
> `openinference-instrumentation-anthropic`, and `anthropic[bedrock]`. The first build
> takes a few minutes — that's expected.
>
> The task env needs two env vars set on it, so they exist in the *task pod*, not just in
> your sandbox: `PHOENIX_COLLECTOR_ENDPOINT` pointed at the in-cluster Phoenix URL ending
> in `/v1/traces`, and `AWS_REGION=us-east-1` (the Bedrock client won't infer the region).
> Check the Flyte MCP for how to declare env vars on a `TaskEnvironment`.
>
> Write one task, `ask`, that takes a question string and:
> 1. Calls `phoenix.otel.register(project_name="workshop-11", auto_instrument=True, batch=False)`.
> 2. Uses `AnthropicBedrockMantle` with model `anthropic.claude-sonnet-5` to ask Claude the
>    question.
> 3. Returns the answer text.
>
> Then run it with `flyte run` asking something short like "In one sentence: what is a span
> in distributed tracing?" and show me the execution URL and the full output.

### ✅ Checkpoint 2: a span from your own cluster, in your own Phoenix

Two tabs, both green:

- **Flyte UI**: the execution succeeded and the task returned an answer.
- **Phoenix UI**: a project called `workshop-11` now exists, with one trace in it. Open it.
  Click the span.

You should see the model name, your full prompt, the full completion, input and output
token counts, and the latency. Nobody wrote code to record any of that.

If Phoenix is empty, don't move on — the rest of this section and all of section 3 are
about exactly that.

### 💡 Understand what just happened

**The instrumentor never noticed it was Bedrock.** This is my favorite fact in the module,
and it's a small lesson in why layering matters.
`openinference-instrumentation-anthropic` patches one thing:
`anthropic.resources.messages.Messages`. And `Anthropic` (direct API), `AnthropicBedrock`,
and `AnthropicBedrockMantle` **all share that exact class** — the transport underneath
differs, the class that builds and sends the request does not. So the instrumentor had no
idea your bytes went to Bedrock over SigV4 instead of to the Anthropic API over a bearer
token, and it didn't need one. You changed clouds and your telemetry required **zero
changes**. Notice when a library gives you that; it's the mark of an abstraction drawn in
the right place.

> ⚠️ **The corollary is a trap.** There *is* a package called
> `openinference-instrumentation-bedrock`. It is a **different package** and it instruments
> the boto3 `bedrock-runtime` client. Point it at `AnthropicBedrockMantle` and you get
> **zero spans, silently** — because it's patching a class your code never touches. It's the
> obvious-looking choice and it's the wrong one. "I'm on Bedrock, so I want the Bedrock
> instrumentor" is a sentence that costs an afternoon. Instrument **the client library you
> actually call**, not the cloud it happens to reach.

**`register()` is doing three jobs.** It creates an OpenTelemetry tracer provider, wires up
an exporter aimed at your Phoenix endpoint, and registers it globally so instrumentation
can find it. You never pass it around; the instrumented libraries pick it up from the
global.

**It found your endpoint without you passing one.** `register()` reads
`PHOENIX_COLLECTOR_ENDPOINT` from the environment. You can also pass `endpoint=`
explicitly, set `PHOENIX_PROJECT_NAME` instead of the `project_name=` argument, or push
extra headers via `PHOENIX_CLIENT_HEADERS`. There's a `PHOENIX_API_KEY` too, which becomes
an `Authorization: Bearer …` header — you don't need it against your own unauthenticated
in-cluster Phoenix, but you would against a hosted one.

> ⚠️ Phoenix's collector also accepts stock OTLP, so `OTEL_EXPORTER_OTLP_ENDPOINT` "works"
> too. **Use the `PHOENIX_*` variables anyway.** `register()` reads those first, so if both
> are set and disagree, your spans go to the `PHOENIX_*` one and the `OTEL_*` one you were
> staring at is a red herring. Pick one family. Make it `PHOENIX_*`.

**`auto_instrument=True` only instruments libraries that are actually installed.** It scans
for `openinference-instrumentation-*` packages and activates the ones it finds. The image
has the Anthropic one, so Anthropic calls get traced. If you'd used OpenAI without
`openinference-instrumentation-openai` installed, you'd get **no spans and no error
message** — the call would work perfectly and Phoenix would stay empty forever. This is the
number one cause of "why is my Phoenix empty?" There are packages for `-openai`,
`-llama-index`, `-langchain`, `-crewai`, and plenty more; one per framework, and you get
exactly the ones you install.

**`batch=False` is not a detail.** It's the whole next section.

---

## 3. The flush gotcha

This is the heart of the module. Read this part properly.

Here's the default setup you'll find in every tracing tutorial. Spans go into a
`BatchSpanProcessor`, which buffers them in memory and exports them on a background thread
every few seconds. This is the right design almost everywhere: batching means one HTTP
request instead of fifty, and it never blocks your hot path.

Now put that inside a Flyte task.

Your task calls Claude, gets a span, hands it to the buffer, returns its result, and the
process exits. The batch interval hasn't elapsed. The background thread never gets to run.
**The pod is gone and your spans went with it.** No exception. No warning. No log line.
Phoenix just sits there empty while the Flyte UI shows a cheerful green check, because from
Flyte's point of view *nothing went wrong* — the task did its job and exited 0.

Short-lived processes are the pathological case for batched telemetry, and **Flyte tasks
are short-lived by design.** Every one of them. This is not an edge case here, it's the
default shape of everything you will ever build on this platform. Same story with Lambda
functions, CLI tools, cron jobs, and CI steps.

Let's watch it happen, then fix it.

> Copy `work/trace_one.py` to `work/trace_batch.py` and change one thing: use `batch=True`
> in the `register()` call. Change the project name to `workshop-11-batch` so we can tell
> the two apart. Run it, show me the execution URL, and tell me whether the task succeeded.

### ✅ Checkpoint 3a: green in Flyte, nothing in Phoenix

Flyte says success and shows you the answer. In Phoenix, `workshop-11-batch` is either
missing entirely or empty.

That gap between the two tabs is the entire lesson. **Nothing reported an error.** If you
were on call, staring at a dashboard that just stopped having data in it, this is what it
would look like.

*(If a span did sneak through: your task ran slow enough for the batch timer to fire, or
the interpreter shut down cleanly enough to flush. Both happen. It's non-deterministic —
which is worse, not better. A bug that appears in 1 run out of 20 is a bug you'll chase for
a week.)*

Now fix it.

> Fix `work/trace_batch.py` so the spans actually arrive, keeping `batch=True`. Use the
> tracer provider as a context manager (`with register(...) as tracer_provider:`) so
> shutdown is guaranteed, or call `tracer_provider.shutdown()` in a `finally:` block.
> Explain which you chose and why. Then re-run it.

### ✅ Checkpoint 3b: the spans arrive

Same code, same batching, and now `workshop-11-batch` in Phoenix has your trace in it. The
only difference is that something drained the buffer before the process died.

### 💡 Understand what just happened

You have three ways out of this, and they're different trades:

**1. `tracer_provider.shutdown()` in a `finally:`.** Flushes the buffer and tears down the
provider. `finally:` matters — if your task raises, that's precisely when you most want the
spans, because the trace of the failing call is the whole point.

**2. Context manager: `with register(...) as tp:`.** Same thing, but the language enforces
it. Harder to forget, harder to accidentally delete during a refactor.

**3. `batch=False`.** Swaps `BatchSpanProcessor` for `SimpleSpanProcessor`, which exports
each span synchronously the moment it ends. There is no buffer, so there's nothing to lose.
The cost is that every span becomes a blocking network round trip in the middle of your
task.

**There's also `force_flush()`,** which drains the buffer without tearing the provider
down. Reach for it when you want spans visible *now* — at a checkpoint mid-task, before a
long stretch of non-LLM work — but intend to keep tracing afterward.

**For this workshop, use `batch=False`.** Our tasks make a handful of model calls, each
taking hundreds of milliseconds, and Phoenix is one hop away on the same cluster, so a few
extra round trips are noise. It removes an entire category of "where did my spans go" from
your afternoon. It just works.

**In production, use batching plus an explicit shutdown.** Once a task is emitting hundreds
or thousands of spans, `SimpleSpanProcessor` means hundreds or thousands of blocking HTTP
requests interleaved with your actual work, and your telemetry starts setting your latency.
Batching amortizes that away. The discipline you're buying with `shutdown()` is small and
the payoff is real.

And note what makes this hard: **the failure is silent.** Telemetry is not allowed to crash
your application, so the OTel SDK swallows export problems. That's the correct engineering
decision and it's the reason this bug is so nasty. Hold onto that thought — we come back to
it at the end.

---

## 4. Trace a real agent

One span is a nice hello. The reason anyone actually installs Phoenix is the *tree*.

An agent doesn't make one model call. It makes a call, gets back a request to use a tool,
runs the tool, feeds the result back, calls again, and loops until it's done or gives up.
That's five to fifteen model round trips and a pile of tool invocations, and when the
answer is wrong, "the LLM was wrong" is not a diagnosis. You need to see which step went
sideways. That's a trace.

You parsed a stack of PDFs in Module 10. Let's put a small agent on top of them.

> Build `work/pdf_agent.py`. Reuse the parsed PDF text from Module 10 — if it's not handy,
> re-parse two or three documents first, or take a path/URL as an argument.
>
> Write a Flyte task `answer_question(question: str) -> str` that runs a small tool-calling
> agent loop with `AnthropicBedrockMantle` and `anthropic.claude-sonnet-5`. Give the model
> two tools: `search_documents(query)` which does simple keyword matching over the parsed
> text and returns matching chunks, and `get_document_summary(doc_id)`. Loop: call the
> model, execute any tool calls it requests, feed the results back, repeat until it returns
> a final answer. Cap it at 6 iterations so it can't spin.
>
> Set up Phoenix the same way as before — same in-cluster endpoint,
> `register(project_name="workshop-11-agent", auto_instrument=True, batch=False)` — and wrap
> the whole agent loop in a custom span named `agent_loop` so I can see the model calls
> nested inside it. Check the `phoenix.otel` / OpenTelemetry docs for how to create a manual
> span if you're not sure.
>
> Run it with a question that actually needs the documents, and show me the execution URL.

### ✅ Checkpoint 4: the span tree

In Phoenix, open `workshop-11-agent` and open the trace. You should see a tree, not a list:
`agent_loop` at the root, with several LLM spans as children, one per turn.

Walk it. On each LLM span, look at the input messages — notice that the conversation grows
on every turn as tool results get appended. Look at the tool-use blocks in the output:
that's the model *deciding* to call your function. Look at token counts climbing turn over
turn. Look at the latency waterfall and find where the time actually went.

Then ask yourself the question this view is for: **did the agent take a stupid path?** Did
it search three times for nearly the same thing? Did it get a good answer on turn one and
then keep going anyway? That's not visible in a green check mark. It's obvious here.

### 💡 Understand what just happened

**You wrote one span; the rest were free.** `agent_loop` is yours. Every LLM span
underneath it came from the auto-instrumented Anthropic client. Nesting happened by itself
— OpenTelemetry keeps the current span in a context variable, so any span started while
yours is active becomes its child. That's why the tree matches your call stack without you
ever wiring parent to child.

**This is the same picture regardless of framework.** OpenInference is a set of conventions
for what an LLM span should contain — the model, the messages, the tokens, the tool calls.
Swap the hand-rolled loop for LlamaIndex or LangChain, install that framework's
instrumentation package instead, and you get a comparable tree without touching Phoenix.
Your telemetry isn't married to your framework choice.

**Latency ≠ compute.** The waterfall is mostly the model thinking, not your CPU. That's
worth internalizing when you go to size resources on these tasks: an agent task is usually
a task that sits and waits. Which, as it happens, is one more reason to keep an eye on the
Flyte side.

---

## 5. Fan out, and join the two views

Last piece, and the one that ties the day together.

Everything so far was one execution. Now run the agent across a batch of questions with
`flyte.map`, and watch N traces land in Phoenix while N tasks run in parallel in Flyte.

But here's the thing that makes it useful instead of just impressive. You'll have ten
traces in Phoenix and ten task attempts in Flyte, and by default **nothing connects them.**
You'll spot a trace that burned 40,000 tokens and have no way to find which Flyte task that
was, whether it was a retry, or what it cost you in compute. So you're going to fix that:
stamp the Flyte execution ID onto the spans as an attribute. Then a weird trace in Phoenix
is one search away from its execution in Flyte, and vice versa.

> Extend `work/pdf_agent.py` with a task `answer_many(questions: list[str]) -> list[str]`
> that uses `flyte.map` to run `answer_question` over all the questions in parallel. Check
> the Flyte MCP for `flyte.map`'s exact signature.
>
> Also: ask the Flyte MCP how to read the current execution ID (and the action or task name,
> and the retry attempt) from the run context via `flyte.ctx()` — don't guess the attribute
> names, look them up. Then set those as attributes on the `agent_loop` span, using keys
> like `flyte.execution_id`, `flyte.task_name`, and `flyte.attempt`.
>
> Run it with 10 questions. Show me the execution URL, and tell me which `flyte.ctx()`
> attributes you used and where in the MCP docs you found them.

### ✅ Checkpoint 5: both tabs, same story

- **Flyte UI**: one parent execution, ten child tasks running in parallel. You've seen this
  shape since Module 02 — the fan-out, the concurrency, the timeline.
- **Phoenix UI**: ten traces in `workshop-11-agent`. Sort by token count. Sort by latency.
  They are not all the same, and the spread is the interesting part.

Now pivot. Pick the most expensive trace in Phoenix, read its `flyte.execution_id`
attribute, and find that exact execution in the Flyte UI. Then go the other way: grab an
execution ID from Flyte and search Phoenix for it.

That round trip — Phoenix to Flyte and back — is the punchline of the module.

### 💡 Understand what just happened

**Two systems, two questions, one ID.**

| | Flyte answers | Phoenix answers |
|---|---|---|
| Ran at all? | ✅ | — |
| Retried, and why? | ✅ | — |
| How parallel? What resources? | ✅ | — |
| Lineage, caching, inputs/outputs | ✅ | — |
| What was the prompt? | — | ✅ |
| How many tokens? What did it cost? | — | ✅ |
| Which tool did the agent pick, and why? | — | ✅ |
| Where did the latency go, per model call? | — | ✅ |

Neither column is a subset of the other, which is why "can't Flyte just show me the prompt?"
is the wrong instinct. An orchestrator that also tried to be an LLM observation tool would
be worse at both. The right move is two systems that each do their own job well and a shared
key between them. You just built the shared key, and it took one span attribute.

**Retries make this sharper.** Remember from Module 03 that every retry is a brand-new pod.
So a retried task gives you *two* traces in Phoenix for one logical unit of work, and
without `flyte.attempt` on the span you'd be staring at a mysterious duplicate wondering if
your agent had gone haywire. With it, the story reads straight off the attribute.

**And notice where both systems live.** Your tasks, your traces, your dashboard, your
orchestrator — all on one EC2 box in your own account, deployed with one CLI. The whole
loop, closed, with nothing external. That's not a workshop simplification. For teams whose
prompts contain things they'd rather not hand to a vendor, it's often the only architecture
on the table, and you just built it in about five minutes.

---

## The three silent failures

Count them up. In 75 minutes you've now seen three separate ways to arrive at an empty
Phoenix UI:

1. **The missing instrumentor.** `auto_instrument=True` found no package for your library,
   so it instrumented nothing.
2. **The wrong instrumentor.** `openinference-instrumentation-bedrock` patching a boto3
   class your Anthropic client never touches.
3. **The unflushed buffer.** `BatchSpanProcessor` holding spans in memory when the pod died.

And a fourth, if you'd left `Scaling` at its default: Phoenix scaled to zero and took its
own database with it.

**Not one of them raises. Not one of them logs. Not one of them turns anything red.** In
every case each system involved reports complete success, because observability tooling is
built — correctly — never to break the application it's watching. The price of that design
is that its own failure mode is *silence*, and silence looks exactly like "nothing has
happened yet."

So here's the thesis of this module, and the habit worth taking home:

**You verify observability by looking, not by the absence of errors.** After you wire up
tracing, go open the UI and confirm a span landed. Put that check in your deploy. Alert on
the *absence* of telemetry, because nothing else will. This is the same instinct the whole
workshop has been drilling — when Kiro says it worked, go look at the Flyte UI — turned
around and pointed at your instrumentation instead of your agent.

---

## Push it further

Pick one. There's more here than fits in 75 minutes.

- **Break something and read the trace.** Give a tool a bug that returns nonsense, then find
  the exact turn where the agent gets confused. This is the actual daily use of Phoenix and
  it's much more convincing than a happy path.
- **Make Phoenix survive.** Point it at Postgres with `PHOENIX_SQL_DATABASE_URL`, set
  `replicas` back to the `(0, 1)` default, and confirm your traces are still there after it
  scales to zero and back. That's the production shape.
- **Deploy something else as an app.** `AppEnvironment` doesn't care that it was Phoenix. A
  Streamlit dashboard over your Module 10 outputs is about fifteen lines.
- **Prove a silent failure to yourself.** Swap in `openinference-instrumentation-bedrock`
  and watch a perfectly healthy agent emit precisely nothing. Now you'll recognize it in the
  wild.
- **Measure what batching buys.** Run the same agent with `batch=True` (plus a proper
  shutdown) and `batch=False`, and compare task duration in the Flyte UI. Then imagine the
  gap at 1,000 spans.
- **Push the cost data back into Flyte.** Take token counts out of the agent loop and render
  them as an HTML report with `flyte.report` (Module 04), so the Flyte UI shows a cost
  summary right on the execution.
- **Try an evaluation.** Phoenix does more than tracing — it can run LLM-as-judge evals over
  the traces you've collected and attach scores to spans. That's the next thing to read
  about: `arize.com/docs/phoenix`.

> **If you don't have a cluster.** Arize runs a hosted Phoenix with a self-serve free tier
> at `app.phoenix.arize.com` — sign up with Google or GitHub, no credit card, and you get a
> Space, an API key, and a collector endpoint. Everything in this module works against it
> unchanged: set `PHOENIX_COLLECTOR_ENDPOINT` to your Space's URL and `PHOENIX_API_KEY` to
> your key, and `register()` picks up both. It's the fastest way to try Phoenix from a
> laptop, and it comes with span and retention quotas worth reading before you fan out to a
> thousand items. (The hostname is `app.phoenix.arize.com` — the bare `phoenix.arize.com`
> doesn't resolve, and the docs live at `arize.com/docs/phoenix`.) We didn't use it today
> because you have something better: a cluster of your own.

---

**Next:** [99 — Now you drive](99-now-you-drive.md) — build something of your own.
