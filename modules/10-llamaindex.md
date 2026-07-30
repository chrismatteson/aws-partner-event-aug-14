# 10 -- LlamaIndex: parse a stack of PDFs in parallel

**~60 minutes.** You'll take a folder of genuinely unpleasant PDFs, parse all of them at
once on your devbox, make re-runs nearly free, and then spend real money on *only* the
pages that deserve it.

This is the module where the day's pieces click together. You already know how to fan a
task out (Module 02) and how to give a task retries and resources (Module 03). Now the
inputs are real documents, the parallelism saves real minutes, and the escalation step
saves real dollars. Same primitives, higher stakes.

Document parsing is a nice shape for this. Most pages in most PDFs are boring -- a
paragraph, a heading, a footer -- and cheap tools handle them perfectly well. A few pages
are horrible: a scanned table, a form with nested cells, numbers baked into pixels. Cheap
tools mangle those; expensive tools handle everything but charge you for the boring pages
too. The move you'll build: run the cheap thing over everything, *notice* which pages it
struggled with, and send only those to the expensive thing.

The PDFs are already in the repo, at **`corpus/`** -- about 10 IRS forms, stable and
public, full of exactly the kind of dense ruled tables that break naive parsers. Point
your code at `corpus/` and leave it there. Put scratch code in **`work/`**, as always.

---

## ⚠️ Read this before Kiro writes a single line of LlamaParse code

This module has a trap, and it goes wrong *silently* -- you get confident,
well-structured, completely dead code.

The old LlamaParse SDKs -- `llama-parse` and `llama-cloud-services` -- hit **end of
maintenance on May 1, 2026**. They talk to **API v1**. The current SDK is
**`llama-cloud>=2`**, and it talks to **API v2**: different endpoints, different concepts,
different results. Not a drop-in swap.

Here's why it bites *you* specifically: every blog post, every Stack Overflow answer, and
most of the training data inside every coding model predates this change. The old API is
overwhelmingly more represented on the internet, so the statistically likely thing for an
agent to write is the dead thing. Your tell:

```python
from llama_parse import LlamaParse     # ← STALE. Stop.
```

If you see that import -- or anything about `parse_mode` or `parse_page_without_llm` --
Kiro has pattern-matched on old data. Don't debug it. Tell Kiro that SDK is deprecated
and have it check the current LlamaIndex docs and rewrite against `llama-cloud` v2 / API
v2, then tell you which docs page it used. This is the same muscle as Setup Checkpoint B,
where a missing MCP made Kiro invent Flyte v1 APIs: **a confident model reaching for the
popular past instead of the current present.** Catching it is the skill.

---

## 1. Parse one PDF with LiteParse

Start as small as possible: one PDF, one task, no API key, no cloud, no credits.

The point of this step isn't the parsing -- it's establishing that parsing a document is
just *Python running in a task*. There's no special document-processing service here.
It's a function. Flyte runs functions.

LiteParse runs fully local, inside your task's pod. But it shells out to Tesseract and
poppler for OCR and page rasterization, so those have to be in the image -- and this is a
quiet failure: without them, LiteParse doesn't error, it silently falls back to
text-layer-only extraction and returns nothing useful for scanned pages. You'd blame the
parser when a dependency was missing.

> **Your task:** Write a Flyte v2 script in `work/` that parses a single PDF from
> `corpus/` with LiteParse. One `TaskEnvironment`, one task that takes a PDF path and
> returns the character count plus the first ~500 characters of extracted text. Run it and
> get the execution URL.

> **Hints:** The parser is the `liteparse` package -- roughly
> `LiteParse().parse(path).text` for the extracted content; confirm the exact surface
> against `developers.llamaindex.ai/liteparse/`. Build the image with
> `flyte.Image.from_debian_base()`, add the OCR system deps with
> `.with_apt_packages(...)` (Tesseract and poppler), and add the parser with
> `.with_pip_packages("liteparse", ...)`. No API key for this step. Confirm the v2
> `TaskEnvironment` / `@env.task` signatures against the Flyte MCP. The first build is
> slow (apt packages); after that it's cached, so build this image once and reuse it for
> every task in the module.

### ✅ Checkpoint

Open the execution in the **Flyte UI** at `https://$FLYTE_DOMAIN/v2`.

- The execution reaches **Succeeded**.
- The task's **output** shows a character count well above zero and a recognizable chunk
  of IRS prose -- form numbers, instructions, something that reads like a document rather
  than mojibake.

If the count is zero or the text is garbage, the parse ran but found no text layer -- tell
Kiro and ask whether that PDF is a scan (and whether the apt packages actually landed in
the image). Kiro will tell you it worked. Go look anyway.

### 💡 Understand

Ask Kiro: what exactly got shipped to the cluster on this run -- the image, or just your
code? Have it draw the line between the image (built once, cached) and the code bundle
(a tarball of your `.py` files that rides alongside). That split is why re-runs are fast
even though your task executes remotely, and it's what makes the next hour feel fast
instead of agonizing.

---

## 2. Fan out with `flyte.map`, then cache

You have ~10 PDFs. A `for` loop parses them one at a time and the wall-clock time is the
*sum* of every parse. That's fine at 10 documents. It is not fine at 10,000, and the code
you write at 10 is the code you'll be stuck with at 10,000.

`flyte.map` fans the same task out across a list. Each input gets its own action -- its
own pod, retries, logs, and place in the UI -- and they run side by side, so wall-clock
time becomes roughly the *slowest single document*, not the sum. They also fail
independently: one corrupt PDF doesn't take down the batch.

Then re-run it. With nothing changed, it parses all ten again from scratch, because
Flyte v2 defaults `cache` to `"disable"` -- it refuses to guess when two runs are "the
same." If you want caching, you ask for it. And the interesting cache key isn't the
*filename* (a file called `f1040.pdf` might be revised tomorrow) -- it's the **content**.
Key the parse on a hash of the file's bytes and unchanged bytes never re-parse, one
changed byte does, and the same document under a new name is still a hit.

> **Your task:** Extend the script to parse **every** PDF in `corpus/` in parallel with
> `flyte.map` -- a parent discovers the PDFs, fans out the parse, and collects structured
> results per file (name, char count, page count, duration) into a summary. Then add
> caching keyed on each PDF's **content**, so unchanged bytes mean no re-parse and one
> changed byte forces one. Run it twice back to back, and show both execution URLs.

> **Hints:** Confirm `flyte.map`'s signature against the Flyte MCP -- not `map_task`
> (that's v1). For caching, ask the MCP about `cache` / `flyte.Cache` in v2 and which
> level it belongs at (`TaskEnvironment`, `@env.task`, or `.override`), then think about
> what the task's inputs must be for the cache key to have the content-hash property.
> Have Kiro explain its caching reasoning *before* it writes code -- there's more than one
> way to make the key depend on content, and the choice has consequences.

### ✅ Checkpoint

Open the execution in the Flyte UI **while it's still running.** You should see **one
child action per PDF**, all **running at the same time** -- not marching one after
another. Click into any single child: it has its own inputs, outputs, logs, and retry
count. You wrote one function and got ten independently observable executions, running
concurrently, for free. The same line gives you ten thousand.

If they ran one at a time, you probably have a `for` loop with an `await` inside it, which
serializes -- ask Kiro to show you the line where the fan-out happens.

Now the second run: the children complete essentially instantly and the UI marks them
**cached** -- the task never executed, Flyte handed back prior outputs. To prove the other
half of the contract, copy one PDF into `work/`, change a single byte, and re-run over a
list that includes the modified copy alongside the original corpus. You want to see
**nine cached, one re-parsed**. If everything re-ran, the key picked up something
incidental (a path, a timestamp); if nothing re-ran, the key is ignoring content entirely
and will serve stale answers forever.

### 💡 Understand

Ask Kiro two things via the MCP. First: what parameter caps how many map actions run at
once? You'll need it in section 3 against a rate-limited API. Second: what would you
*actually* have to do to force a re-parse after changing the task's **code** but not its
inputs -- does Flyte hash the function body, or is there an explicit version you bump?
That's the classic caching footgun; better to meet it here than in production at 2am.

---

## 3. Escalate only the hard pages to LlamaParse

Now the payoff -- the pattern worth carrying out of this room.

Go look at the LiteParse output for a page with a dense ruled table. Somewhere in there a
table has been flattened into a soup of numbers with the row and column structure thrown
away. LiteParse read the *text*; it didn't read the *table*. You could ship it (wrong
numbers, silently) or run everything through LlamaParse's best tier (correct, and you pay
premium rates for thousands of pages that say "This page intentionally left blank"). The
good option: let the cheap pass tell you where it struggled, and fan *only those* pages
out to the cloud. Same instinct as Module 03's per-task resources -- spend the scarce
resource where it earns its keep. Here the scarce resource is **credits**.

### The credit math, before you spend any

Your free plan has **10,000 credits per month**, and the tier sets the rate:

| Tier | Credits per page |
|---|---|
| **Fast** | **1** |
| Cost-effective | 3 |
| Agentic | 10 |
| Agentic Plus | 45 |

Run Agentic over 50 PDFs at 10 pages each and that's 5,000 credits -- half your monthly
allowance in one exercise. When credits run out the free plan returns **402** and stops;
there's no pay-as-you-go fallback. So pin **`tier="fast"`**: at 1 credit/page you can
afford to be curious, and Fast is the right call for a *targeted* second look at a handful
of fumbled pages. If Fast still mangles a page, *that's* the evidence that justifies
escalating that one page to Agentic -- 10 credits on one page instead of on ten thousand.

There's a second limit that shapes the exercise: **20 requests per minute**, scoped to
your org. Fan 50 documents out at once and your own map trips your own rate limit and
starts collecting **429s**. This is why the corpus is ~10 documents, not 50 -- ten fits
comfortably under 20 RPM.

`LLAMA_CLOUD_API_KEY` is already in your task env from SSM, so you don't wire up the key --
you just use it.

> **Your task:** Add a selective escalation pass. Stage 1 is your cached LiteParse pass
> over everything. Stage 2 is a heuristic that flags poorly-parsed pages -- table-heavy,
> low-confidence, suspiciously little text for the page. Stage 3 fans **only the flagged
> pages** to LlamaParse via `flyte.map`. The parent returns a summary: pages handled
> locally, pages escalated, the escalation percentage, and approximate credits spent. Run
> it and show the execution URL.

> **Hints:** Use the **`llama-cloud>=2`** SDK -- *not* `llama-parse` or
> `llama-cloud-services` (both end-of-life, v1 API; see the warning up top). Pin
> `tier="fast"`. The v2 call shape is roughly `client.files.create(...)` to upload, then
> `client.parsing.parse(file_id=..., tier="fast", ...)` to parse -- confirm the exact
> method names and arguments against the current LlamaIndex docs before relying on it, the
> surface may have drifted. The 20 req/min limit means you need the `flyte.map` concurrency
> cap from section 2. Give the LlamaParse task retries with backoff (ask the MCP about
> `flyte.RetryStrategy` and `flyte.Backoff`): a 429 means slow down and retry, a 402 means
> credits exhausted -- don't retry that. Cache this task on content too. Have Kiro explain
> its escalation heuristic *before* it codes it.

### ✅ Checkpoint

In the Flyte UI, one execution tells the whole economic story off the graph: a **wide
stage 1** (every document, LiteParse, free, mostly cached on a re-run) next to a **narrow
stage 3** (a handful of flagged pages going to LlamaParse). The summary reports the
escalation rate -- a few percent is the shape you're looking for.

Click into one escalated page and compare its LlamaParse markdown against what LiteParse
produced for the same page. **This is the moment the module is built around.** You should
see an actual markdown table -- pipes, headers, aligned columns -- where LiteParse gave
you a flat run of numbers. That narrow branch next to the wide one *is* the lesson: you
paid cloud prices for a sliver of the corpus and got cloud quality exactly where it
mattered.

If *nothing* escalated, the heuristic is too strict -- ask Kiro to show its flagging
decision for the worst-looking table page. If *everything* escalated, it's too loose and
you've rebuilt "run everything through the cloud" with extra steps. Tighten it.

### 💡 Understand

Ask Kiro to walk the cost model: for 10,000 PDFs at 10 pages each, at your escalation
rate, compare credits for this design vs. LlamaParse Fast over everything vs. Agentic over
everything. Then the harder question: where does this design *break*? What documents would
fool the heuristic, and what happens if the corpus shifts from IRS forms to handwritten
medical notes? The pattern you built is good, and it is not unconditionally good, and the
difference between those two statements is most of engineering.

---

## Push it further

Pick one. There's more here than fits in the time, and that's fine.

- **Make the heuristic earn its keep.** Escalate a random 10% *in addition* to the flagged
  pages and compare output on the random sample. That tells you your false-negative rate --
  how many bad pages are you shipping without knowing?

- **Add a report.** [Module 03](03-resilience.md) gave you `flyte.report`. Render a
  side-by-side of LiteParse vs. LlamaParse markdown for every escalated page, right in the
  execution UI.

- **Escalate the escalation.** Pages that come back bad even from `tier="fast"` get one
  more hop to `tier="agentic"` -- 10 credits, on maybe a dozen pages in the whole corpus.
  Three tiers, each an order of magnitude more expensive and rarer. That's the real
  production shape.

- **Deploy it.** [Module 03](03-resilience.md) showed you how to make a pipeline a named
  entity on the backend. Do it to this one -- now "parse this corpus" is something you
  *invoke*.

- **Chase the stale-SDK trap on purpose.** In a fresh task, ask Kiro to write the
  LlamaParse call *without* telling it about the v1/v2 split. See what it reaches for.
  That's the default behavior of every agent your team will use next week, on every
  library that changed recently. Worth seeing once with your own eyes.

---

**Next:** [11 -- Arize Phoenix: trace an agent running inside Flyte](11-arize-phoenix.md)
