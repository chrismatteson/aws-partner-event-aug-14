# 10 -- LlamaIndex: parse a stack of PDFs in parallel

**90 minutes.** You'll take a folder of genuinely unpleasant PDFs, parse all of them at
once on your devbox, make re-runs nearly free, and then spend real money on *only* the
pages that deserve it.

This is the module where the day's pieces click together. You already know how to fan a
task out (Module 02) and how to give a task retries and resources (Module 03). Now the
inputs are real documents, the parallelism saves real minutes, and the escalation step
saves real dollars. Same primitives. Higher stakes.

The document-parsing problem is a nice shape for this. Most pages in most PDFs are
boring -- a paragraph of text, a heading, a footer. A few pages are horrible: a scanned
table, a form with nested cells, a chart with numbers baked into pixels. Cheap tools
handle the boring 95% perfectly well and mangle the ugly 5%. Expensive tools handle
everything, and charge you for the boring pages too.

The lazy answer is to pick one tool. The good answer -- the one you'll build -- is to run
the cheap thing over everything, *notice* which pages it struggled with, and send only
those to the expensive thing.

---

## Your corpus

The PDFs are already in the repo, at **`corpus/`**. They're IRS forms: stable, public,
no auth, and full of exactly the kind of dense ruled tables that break naive parsers.
About 10 documents.

> **Why not download something live?** Because arXiv and SEC EDGAR rate-limit by *IP
> range and user agent*, not per account, and forty people in one room hitting them in
> the same ninety seconds is precisely the traffic pattern they exist to throttle. The
> corpus is in the repo so the interesting part of this module is the parsing, not the
> 429s. Point your code at `corpus/` and leave it there.

Put your scratch code in **`work/`**, same as every other module.

---

## The two tools, honestly

You're about to use two things from the LlamaIndex world. They are not competitors and
this is not a sales pitch -- they're different points on a cost curve.

| | **LiteParse** | **LlamaParse** |
|---|---|---|
| Where it runs | Fully local, in your task's pod | LlamaIndex's cloud |
| Cost | Free, open source (MIT-ish, Rust core) | Credits, per page |
| API key | **None** | `LLAMA_CLOUD_API_KEY` |
| Speed | Fast -- no network round trip | Slower -- it's an HTTP call |
| Good at | Text, simple layout, basic OCR (Tesseract) | Dense tables, scans, layout that needs a model to read |
| Bad at | Anything that needs *understanding* the page | Your budget |

LiteParse shipped in March 2026 -- [github.com/run-llama/liteparse](https://github.com/run-llama/liteparse),
docs at [developers.llamaindex.ai/liteparse/](https://developers.llamaindex.ai/liteparse/).

> One honest caveat worth knowing before you build on it: **LiteParse is TS/Node-native
> with a Python wrapper.** The Rust core and the TypeScript bindings are where the
> project's center of gravity is; Python is a first-class wrapper but a wrapper. In
> practice that means the Python surface can lag the TS one, and the failure modes are
> occasionally wrapper-shaped rather than parser-shaped. It's fine -- just know which
> layer you're standing on when something's weird.

Everything in `corpus/` is public IRS paperwork, so nothing here is sensitive. If it
were, that would change how you use the cloud tool, and we'll come back to that.

---

## ⚠️ Read this before Kiro writes a single line of LlamaParse code

This is the number-one way this module goes wrong, and it goes wrong *silently* -- you
get confident, well-structured, completely dead code.

**The old SDKs are at end of maintenance as of May 1, 2026.** Specifically
`llama-parse` and `llama-cloud-services`. The current SDK is **`llama-cloud>=2`**
(2.11.0 at time of writing, MIT).

This is not a rename. The old SDK talks to **API v1**. The new SDK talks to **API v2**.
Different endpoints, different concepts, different results. **Not a drop-in swap.**

Here's why it bites *you* specifically: every blog post, every Stack Overflow answer,
every tutorial, and most of the training data inside every coding model on earth
predates this change. The old API is overwhelmingly more represented on the internet
than the new one. So the statistically likely thing for an agent to write is the dead
thing.

**Your tell:**

```python
from llama_parse import LlamaParse     # ← STALE. Stop.
```

If you see that import, or anything about `parse_mode`, or `parse_page_without_llm`,
Kiro has pattern-matched on old data. Don't debug it. Make it go look:

> That import is from the deprecated `llama-parse` SDK, which hit end of maintenance on
> May 1, 2026. Check the current LlamaIndex documentation and rewrite this using
> `llama-cloud` version 2 or later against API v2. Tell me which docs page you used.

This is the same muscle as Setup Checkpoint B, where a missing MCP made Kiro invent
Flyte v1 APIs. Same failure, different library: **a confident model reaching for the
popular past instead of the current present.** Catching it is a skill. You'll use it
long after today.

---

## The image for this module

Your tasks need `liteparse` and `llama-cloud`, and LiteParse shells out to Tesseract and
poppler for OCR and page rasterization. So the image is:

```python
image=(
    flyte.Image.from_debian_base()
    .with_apt_packages("tesseract-ocr", "poppler-utils")
    .with_pip_packages("liteparse", "llama-cloud>=2")
)
```

Build it once at the start of the module and every task here can share it. The first
build takes a few minutes (apt packages are the slow part); after that, cached.

> ⚠️ **The apt packages are not optional.** Without Tesseract, LiteParse doesn't error --
> it quietly falls back to text-layer-only extraction and returns nothing useful for
> scanned pages. You'd conclude the parser is bad when actually a dependency is missing.
> This is the same shape of failure as everything in [Module 11](11-arize-phoenix.md):
> the tool doesn't break, it just goes quiet.

> **If builds are broken** and a facilitator tells you to skip them, there's a prebuilt
> image with all of this already in it: pin `flyte.Image.from_base(os.environ["WORKSHOP_IMAGE"])`
> and chain nothing onto it. Don't reach for this unless you're told to.

---

## 1. LiteParse, zero friction

Start as small as possible: one PDF, one task, no API key, no cloud, no credits.

The point of this step isn't the parsing -- it's establishing that parsing a document is
just *Python running in a task*. There's no special document-processing service here.
It's a function. Flyte runs functions.

The LiteParse Python API is straightforward: `from liteparse import LiteParse`, then
`result = LiteParse().parse("doc.pdf")`, and `result.text` gives you the extracted
content. Confirm against `developers.llamaindex.ai/liteparse/` if anything doesn't line
up.

> **Your task:** Write a Flyte v2 script in `work/` that parses a single PDF from `corpus/` using LiteParse. Define one `TaskEnvironment` with the image above, one task that takes a path to a PDF and returns the character count plus the first 500 characters of extracted text. Run it and get the execution URL.
>
> **Hints:** The image needs apt packages (tesseract-ocr, poppler-utils) and pip packages (liteparse, llama-cloud>=2). No API key needed for this step. Use the Flyte MCP for the v2 task signature. The first build will be slow.
>
> **Stretch:** Ask Kiro to explain where the work physically happened -- which parts ran in the sandbox vs. in a pod on your devbox, how the PDF got from the repo to the pod, and why `flyte run` is fast when it's shipping code to a cluster.

### ✅ Checkpoint: one PDF, parsed, on the cluster

Open your **Flyte UI** tab at `https://$FLYTE_DOMAIN/v2`.

- A new execution appears and reaches **Succeeded**.
- Click into the task. Its **output** shows a character count well above zero and a
  recognizable chunk of IRS prose -- form numbers, instructions, something that reads
  like a document rather than mojibake.

If the count is zero or the text is garbage, the parse ran but didn't find a text layer.
Say so to Kiro and ask it to check whether that particular PDF is a scan.

Don't move on until you've seen real text in the UI. Kiro will tell you it worked. Go
look anyway.

### 💡 Understand what just happened

If you already asked this in the Stretch above, compare Kiro's answer to this and see if
it covered the key distinction:

`flyte run` ships a **code bundle** -- a tarball of your `.py` files -- not an image.
The image was built once (and cached). Your code rides alongside it. That's why re-runs
are fast even though your task executes on a remote cluster. Understanding that split is
what makes the next hour feel fast instead of agonizing. If Kiro's explanation didn't
draw this line clearly, push it: "What exactly gets uploaded on subsequent runs, and why
is it so much faster than the first?"

---

## 2. Fan out with `flyte.map`

Now the good part.

You have ~10 PDFs. You could loop over them. A loop parses document 1, then document 2,
then document 3, and the wall-clock time is the sum of every parse. That's fine at 10
documents. It is not fine at 10,000, and the code you write at 10 is the code you'll be
stuck with at 10,000.

`flyte.map` fans the same task out across a list of inputs. Each input gets its own
action -- its own pod, its own retries, its own logs, its own place in the UI. They run
side by side. Wall-clock time becomes roughly the time of the *slowest single document*,
not the sum.

And critically: they fail independently. One corrupt PDF doesn't take down the batch.

> **Your task:** Extend your script to parse **every** PDF in `corpus/` in parallel using `flyte.map`. A parent task discovers all PDFs, fans out the parse, collects structured results (filename, character count, page count, parse duration), and returns a summary with totals.
>
> **Hints:** Use the Flyte MCP for `flyte.map`'s exact signature -- do not use `map_task` (that's v1). Think about what structured data to return from each child so the parent can aggregate meaningfully.
>
> **Stretch:** Ask Kiro how many pods Flyte created, what decides that number, and what happens if you pass `flyte.map` a list of 10,000 documents -- does it start 10,000 pods at once? Also ask what happens to the other nine if one PDF is corrupt and raises an exception.

### ✅ Checkpoint: the fan-out, seen

**This is the one to actually stop and look at.** Open the execution in the Flyte UI
while it's still running.

You should see **one child action per PDF**, and they should be **running at the same
time** -- not marching through one after another. Watch the list light up green in a
ragged wave as the short documents finish before the long ones.

Now click into **any single child action**. It has its own inputs. Its own outputs. Its
own logs. Its own retry count. It is a first-class execution that you can inspect,
re-run, and reason about on its own -- even though you never named it, and there are ten
of them.

That's the thing worth internalizing. You wrote one function. You got ten independently
observable executions, running concurrently, for free. The same line of code that gives
you ten gives you ten thousand -- the only difference is how long the list is and how
much your cluster can chew at once.

Compare the parent's reported wall-clock time against the sum of the individual parse
times. The gap between those two numbers is what `flyte.map` bought you. On ten small
PDFs it's modest. Picture the number at corpus scale.

> **If they ran one at a time**, you probably have a plain `for` loop with an `await`
> inside it, which serializes. Ask Kiro: *"Are these actually running concurrently? Show
> me the line where the fan-out happens and explain why it doesn't serialize."*

### 💡 Understand what just happened

If you already asked the Stretch questions above, you have Kiro's answer about pod count
and failure isolation. Now push deeper on two things the Stretch didn't cover:

First, ask about **concurrency controls** on `flyte.map` -- have Kiro check the MCP for
what parameter caps how many map actions run simultaneously, because you will need it in
section 4 when you hit a rate-limited API.

Second, ask the precision question about partial failure: when one input raises, what
does the *parent task* see? Does it get a partial result list? An exception? A mix? That
second question is the one people get wrong when they reason about `map` by analogy to
Python's built-in `map`.

---

## 3. Cache by content hash

Re-run the fan-out you just built. Go on -- same code, same corpus, same everything.

It parses all ten documents again, from scratch, and charges you the same wall-clock
time for the privilege of computing an answer it already knows. Nothing changed. Every
byte of every PDF is identical.

That's the cost of `cache` defaulting to `"disable"` in Flyte v2. It defaults off on
purpose: caching means Flyte has to decide when two runs are "the same," and it refuses
to guess on your behalf. **If you want caching, you ask for it.**

Here's the part that makes it genuinely useful. The interesting cache key isn't the
*filename* -- a file called `f1040.pdf` might be revised tomorrow. It's the **content**.
Key the parse on a hash of the file's bytes, and you get exactly the semantics you want:

- Unchanged PDF -> cache hit -> parse skipped entirely.
- One byte different -> different hash -> re-parsed.
- Same document under a new filename -> same hash -> still a hit.

This is a small idea with a large blast radius. Iterating on a pipeline stops meaning
"re-parse the world every time I change a downstream function."

> **Your task:** Add caching to the per-document parse task, keyed on the **content** of each PDF rather than its path. The requirement: unchanged bytes mean no re-parse; a single byte changed means re-parse. Run the pipeline twice in a row and show both execution URLs.
>
> **Hints:** Ask the Flyte MCP about `cache` and `flyte.Cache` in v2 -- find out which level it belongs at (`TaskEnvironment`, `@env.task`, or `.override`). Think about what the task's inputs need to be for Flyte's cache key to have the content-hash property. Have Kiro explain its reasoning before writing code.
>
> **Stretch:** Ask Kiro what goes into the cache key, where cached outputs physically live, and what happens when you change the *code* of the task but not its inputs -- does Flyte know the function is different?

That "explain your reasoning before you write the code" clause is doing real work. There
is more than one way to make the cache key depend on content, and the choice has
consequences. Make Kiro show you the thinking.

### ✅ Checkpoint: cache hits, in the UI

Two executions, back to back, in the Flyte UI.

**First run:** every child action runs normally.

**Second run:** the child actions complete essentially instantly, and the UI marks them
as **cached**. The task never executed -- Flyte recognized the inputs and handed back the
previous outputs. Total wall-clock time collapses.

Click into a cached child action. Its outputs are there, fully populated, from a task
that didn't run.

Now prove the other half of the contract:

> **Your task:** Copy one PDF from `corpus/` into `work/`, modify a single byte of it, then re-run the pipeline over a list that includes the modified copy alongside the original corpus. Show the execution URL.
>
> **Hints:** You need to see nine cached, one re-parsed. If everything re-ran, the cache key picked up something incidental (path, timestamp). If nothing re-ran, the key is ignoring content entirely.
>
> **Stretch:** Ask Kiro about cache versioning -- what happens if you change the code but not the inputs? How would you force a re-parse after a code change?

**Third run:** nine cached, one re-parsed. If you see that in the UI, your cache key is
keyed on content and you understand it. If *everything* re-ran, the key picked up
something incidental -- a path, a timestamp, a run ID. If *nothing* re-ran, the key is
ignoring content entirely, which is worse: that cache will happily serve you stale
answers forever.

### 💡 Understand what just happened

Ask Kiro to show you exactly what goes into the cache key for your parse task, and walk
through why changing one byte of the PDF changed it. Where do the cached outputs
physically live?

If you already asked the Stretch about cache versioning, compare Kiro's earlier answer to
this: ask the MCP about cache versioning and find out what you'd *actually* have to do to
force a re-parse after a code change. The mechanism is specific and non-obvious -- does
Flyte hash the function body? Does it compare bytecode? Or is there an explicit version
you bump? That's the classic caching footgun and it's better to meet it here than in
production at 2am.

---

## 4. Escalate the hard pages

Now the payoff -- the pattern that's actually worth carrying out of this room.

Your LiteParse pass is fast, local, and free, and it did a fine job on most of the
corpus. But go look at the output for a page with a dense ruled table. Somewhere in
there, a table has been flattened into a soup of numbers with the row and column
structure thrown away. LiteParse read the *text*. It didn't read the *table*.

You have two bad options and one good one.

**Bad option 1:** ship it. Your downstream extraction silently produces wrong numbers
from mangled tables, and nobody notices until someone reconciles a figure by hand.

**Bad option 2:** run everything through LlamaParse's best tier. Correct, and expensive
in a way that scales exactly wrong -- you pay premium rates for thousands of pages that
say "This page intentionally left blank."

**The good option:** let the cheap pass tell you where it struggled. Flag the pages that
look table-heavy or came back low-confidence, and fan *only those* out to the cloud.

A cheap pass over everything. An expensive pass over the 5% that earns it. This is the
same instinct as Module 03's per-task resources -- you gave the one memory-hungry task a
bigger box instead of upsizing the whole cluster. Same move. Different resource. Here,
the scarce resource is **credits**.

### The credit math, before you spend any

Your free plan has **10,000 credits per month**. Tiers:

| Tier | Credits per page |
|---|---|
| **Fast** | **1** |
| Cost-effective | 3 |
| Agentic | 10 |
| Agentic Plus | 45 |

Run Agentic over 50 PDFs at 10 pages each and that's 5,000 credits -- **half your monthly
allowance, in one exercise, before the coffee break**. When the credits are gone, the
free plan returns **402** and stops. There's no pay-as-you-go fallback to quietly catch
you.

> **Pin `tier="fast"` for this module and know why you're doing it.** At 1 credit/page
> you can afford to be curious. Fast is also genuinely the right call here: you're using
> LlamaParse for a *targeted* second look at a handful of pages the cheap parser
> fumbled, not as a document-understanding oracle. If Fast still mangles a page, *that*
> is the evidence that justifies escalating that page again -- and now you're spending 10
> credits on one page instead of on ten thousand.

There's a second limit that shapes the exercise: **20 requests per minute**, scoped to
your org. You each have your own org, so nobody in the room is contending with anyone
else -- but you can absolutely contend with yourself. Fan 50 documents out at once and
your own map will trip your own rate limit and start collecting **429s**.

**This is why the corpus is ~10 documents, not 50.** Ten fits comfortably under 20 RPM.
It's a real constraint, not a toy one, and it's exactly the kind of thing that turns a
clean fan-out into a retry storm if you don't think about it first.

Two more things worth knowing:

- **Uploaded files cache server-side for 48 hours.** Re-parsing the same file inside that
  window doesn't double-charge you. Your Flyte cache and their file cache are separate
  layers doing the same favor.
- **`do_not_cache=True`** opts a document out of that server-side cache. You don't need
  it for IRS forms. You'd want it for anything you can't leave sitting on someone else's
  infrastructure -- and that decision belongs to whoever owns the document, not to the
  person writing the pipeline.

### Getting the API key to the task

`LLAMA_CLOUD_API_KEY` is already a Kiro secret, so it's an environment variable in your
sandbox. But your task doesn't run in your sandbox -- it runs in a pod on your devbox.
The value has to get there deliberately.

Flyte v2 has more than one mechanism for this, and per the steering file both `secrets`
and `env_vars` live on `TaskEnvironment` (and on `.override`), not on `@env.task`. Don't
take my word for which one is right for you -- make Kiro find out.

> **Your task:** Get `LLAMA_CLOUD_API_KEY` from your sandbox into the task pod properly. Ask the Flyte MCP to compare `TaskEnvironment(secrets=...)` against `TaskEnvironment(env_vars=...)` and wire up the appropriate one for an API key. Do not hardcode it, do not print it.
>
> **Hints:** Think about the difference between secrets and plain env vars -- one is for sensitive values that shouldn't appear in logs or the UI. The key exists in your sandbox environment; you need a mechanism to get it into a pod that runs elsewhere.
>
> **Stretch:** Ask Kiro what the actual difference is between `secrets` and `env_vars` on `TaskEnvironment` from a security perspective, and where each one is visible.

### The escalation itself

Here's the architecture: stage 1 is LiteParse over everything (already built, cached).
Stage 2 identifies pages that look poorly parsed -- table-heavy, low-confidence,
suspiciously little text for the page. Stage 3 fans **only the flagged pages** to
LlamaParse with `flyte.map`.

The v2 SDK shape is roughly: `from llama_cloud import LlamaCloud`, then
`client.files.create(file=..., purpose="parse")`, then
`client.parsing.parse(file_id=..., tier="fast", version="latest", expand=["markdown"])`,
and read `result.markdown.pages[0].markdown`. **Verify this against the current
LlamaIndex documentation before relying on it** -- the exact method may have drifted.

> **Your task:** Add a selective escalation pass to the pipeline. LiteParse runs over everything (stage 1, cached). A heuristic identifies poorly-parsed pages (stage 2). Only the flagged pages go to LlamaParse via `flyte.map` (stage 3). The parent returns a summary: pages handled by LiteParse, pages escalated, percentage, and approximate credit usage.
>
> **Hints:** Use `llama-cloud` SDK v2 (not the deprecated `llama-parse`). Pin `tier="fast"`. The rate limit is 20 req/min so you need concurrency control on `flyte.map`. Give the LlamaParse task retries with backoff (`flyte.RetryStrategy` + `flyte.Backoff`). A 402 means credits exhausted (don't retry); a 429 means slow down (retry). Cache this task on content too. Have Kiro explain its escalation heuristic before coding it.
>
> **Stretch:** Ask Kiro to walk you through the cost model: for 10,000 PDFs at 10 pages each, at your current escalation rate, compare credits consumed by this design vs. LlamaParse Fast over everything vs. Agentic over everything. Then ask where this design breaks -- what documents would fool the heuristic?

### ✅ Checkpoint: two tiers, one pipeline

In the Flyte UI, one execution, and you can read the entire economic story off the graph:

- **A wide stage 1** -- every document, fanned out, LiteParse, free. On a re-run, most of
  it cached.
- **A narrow stage 2** -- a handful of flagged pages, and only those, going to LlamaParse.
- The summary output tells you the escalation rate. Somewhere in the neighborhood of a
  few percent is the shape you're looking for.

Click into one escalated page and compare its LlamaParse markdown against what LiteParse
produced for the same page. **This is the moment the module is built around.** You should
see an actual markdown table -- pipes, headers, aligned columns, structure -- where
LiteParse gave you a flat run of numbers.

Now look at the ratio in the graph one more time. That narrow branch next to that wide
one *is* the lesson. You paid cloud prices for a sliver of your corpus and got cloud
quality exactly where it mattered.

> **If nothing escalated**, your heuristic is too strict -- or, less likely, LiteParse
> genuinely handled everything. Ask Kiro to show you the flagging decision for the
> worst-looking table page and explain why it passed.
>
> **If everything escalated**, your heuristic is too loose, and you've built bad option 2
> with extra steps. Tighten it. This is a real tuning problem and getting it wrong in
> both directions is the fastest way to understand it.

### 💡 Understand what just happened

If you already asked the Stretch cost-model question above, you have the arithmetic. Now
push Kiro on the parts the Stretch didn't cover: what breaks if LiteParse gets *better*
next quarter -- does your heuristic start escalating nothing, and is that a problem? What
if the corpus shifts from IRS forms to handwritten medical notes? And which part of this
pipeline would you actually not ship to production without changing? Sit with that answer
for a minute. The pattern you built is good, and it is not unconditionally good, and the
difference between those two statements is most of engineering.

---

## Push it further

Pick one. There's more here than fits in the time, and that's fine.

- **Make the heuristic earn its keep.** Escalate a random 10% *in addition* to the flagged
  pages, then compare LiteParse and LlamaParse output on the random sample. That tells you
  your false-negative rate -- how many bad pages are you shipping without knowing? A
  heuristic with no measurement is a guess with good PR.

- **Add a report.** Module 04 gave you `flyte.report`. Render a side-by-side of LiteParse
  markdown versus LlamaParse markdown for every escalated page, right in the execution UI.
  Suddenly the quality difference is something you can show someone instead of describe.

- **Escalate the escalation.** Pages that come back bad even from `tier="fast"` get one
  more hop to `tier="agentic"` -- 10 credits, on maybe a dozen pages in the whole corpus.
  Three tiers, each one an order of magnitude more expensive and an order of magnitude
  rarer. That's the real production shape.

- **Deploy it.** Module 05 showed you how to make a pipeline a named entity on the
  backend. Do it to this one. Now "parse this corpus" is something you *invoke*, not
  something you run from a file.

- **Break it on purpose.** Drop a corrupt PDF and a password-protected PDF into `corpus/`
  and run it. Does one bad document take down the batch? Should it? What *should* a
  ten-thousand-document parse do when document 4,127 is a zip file someone renamed?

- **Chase the stale-SDK trap on purpose.** Ask Kiro to write the LlamaParse call *without*
  telling it about the v1/v2 split, in a fresh task. See what it reaches for. That's the
  default behavior of every agent your team will use next week, on every library that
  changed recently. Worth seeing once with your own eyes.

---

**Next:** [11 -- Arize Phoenix: trace an agent running inside Flyte](11-arize-phoenix.md)
