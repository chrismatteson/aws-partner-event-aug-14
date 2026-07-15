# 01 — Your first cloud task

**~30 minutes.** Prerequisite: both [setup checkpoints](../setup/) are green.

The central claim of Flyte is that you write **normal Python functions**, mark them as
tasks, and they run on real infrastructure without being rewritten. Not a DSL, not YAML,
not a special API for "cloud mode." Just functions.

That claim is easy to make and worth testing. So let's test it.

---

## Build it

**Prompt Kiro:**

> Using the Flyte MCP for reference, create `work/hello.py` with a Flyte v2
> `TaskEnvironment` named `hello` using `flyte.Image.from_debian_base()`. Add a task that
> takes a `name` string and returns a greeting, and a `main` task that calls it. Then run
> `main` with my name against the devbox and give me the execution URL.

Kiro will write the file, run it, and hand you a URL.

**The first run will take a few minutes.** It's building a container image and pushing it
to your account's registry. That's a one-time cost, and it's worth understanding rather
than waiting through: your function needs somewhere to run, that somewhere is a container,
and Flyte just built one for you from four lines of Python. No Dockerfile, no registry
commands, no CI.

> **Why does it say podman?** Because it is. Flyte's builder wants `docker buildx`; this
> sandbox has podman. `bootstrap.sh` installed a shim that bridges the two. It's a hack,
> it's ours, and it lives in `scripts/docker-shim.sh` if you're curious. If a build fails
> in a way that looks like a weird flag error, that's the first place to look.

Later runs are **fast**. Your code ships separately from the image, as a tarball — a
"code bundle" — so changing a line and re-running doesn't rebuild anything. You only pay
the build cost again when you change the image *definition* (adding a package, say). Keep
that distinction in mind today: **logic is cheap to iterate, dependencies are not.**

---

## ✅ Checkpoint

**Go to your Flyte UI tab** (`https://$FLYTE_DOMAIN/v2`) and open the execution.

You're looking for:

- Status **Succeeded**.
- A task named something like `hello.main`, with a **child action** under it — the
  greeting task it called.
- Your greeting in the outputs.

> **If it hangs on the first try**, your devbox was asleep. It wakes in ~2 minutes. This
> is normal and will happen again after lunch.

**Don't skip the UI visit.** Kiro will tell you it succeeded. Today's habit is not
believing it until the cluster says so. That habit is the actual skill — the code is the
easy part.

---

## 💡 Understand what just happened

**Prompt Kiro:**

> Using the Flyte MCP, explain what `TaskEnvironment` and `@env.task` did here. Why did
> my plain Python function need an "environment" and an "image" to run on a cluster?
> Keep it to a few sentences.

The short version, so you can tell whether Kiro's answer is any good:

Your function has to run *somewhere*. That somewhere is a container on a Kubernetes
node, and a container needs an image. The `TaskEnvironment` is where you say what that
execution context looks like — which image, how much CPU and memory, which secrets. The
`@env.task` decorator is what makes an ordinary function addressable by the cluster: it
gets a name (`hello.main`), typed inputs and outputs, and its own tracked, retryable
lifecycle.

That last part is the bit that matters, and it's why the fan-out in the next module is
free rather than something you have to engineer.

---

## Try this

Ask Kiro to change the greeting and re-run. Watch how long it takes.

That's your feedback loop for the rest of the day: seconds, not minutes, because the
image never changes. Worth internalizing now — it's what makes the parallel stuff in
Module 02 fun instead of tedious.

---

**Next:** [02 — Fan out](02-fan-out.md)
