# 20 — Protopia AI: privacy at inference time

> 🚧 **Stub — not a hands-on module yet.** Read it as background; there's nothing to run.
> If this problem is yours, find the Protopia folks at the event.

## The problem

You want to use a capable model on data you're not allowed to send it. Regulated
records, customer PII, source code, anything under a contract that says it doesn't leave
your boundary. The usual answers are all bad: redact and lose the signal, self-host a
weaker model, or wait six months for a legal review.

## Protopia's answer

**Stained Glass Transform** (SGT). Instead of sending plaintext, you send a *learned,
stochastic transformation of the token embeddings*. The target model reads the
transformed representation and produces good output. A human reading it gets nothing
useful, and neither does another model.

Plaintext never leaves your trust zone. Latency cost is milliseconds.

The privacy claim is grounded in mutual-information estimates over Gaussian mixtures —
see [arXiv:2506.09452](https://arxiv.org/abs/2506.09452), *Learning Obfuscations Of LLM
Embedding Sequences*. Worth being precise: that's an **information-theoretic MI
estimate**, not a differential-privacy guarantee. Different claim, different shape.

## Why it's a stub

**There's nothing you can touch without a sales call.** We checked properly:

- PyPI `stainedglass` is a **1 KB empty placeholder** from 2023 — a name reservation, no
  modules.
- The HuggingFace org lists **zero public models**; the SGT model repos return `401`.
- On AWS Marketplace there are two listings, and the difference matters: the
  Llama-3.1-8B *"with SGT Support"* image is **free and self-serve**, but it's only the
  **receiving end** — stock weights that can read protected prompts. The transform
  itself is **"[Private Offers Only]"**. Subscribe to the free one and you get a working
  Llama endpoint that does nothing privacy-related.
- Protopia's own `safeclaw` repo is real and active, but needs an `SGT_API_KEY` and a
  gated HF model, both "provided by Protopia."

The docs are open. The artifacts are not.

## The Flyte angle (why this is interesting anyway)

**An SGT is model-specific.** Change the model, retrain the transform. That's a training
job with a dependency edge — which is exactly a pipeline:

> Fine-tune a model **and** train its matching Stained Glass Transform in one workflow,
> version them together, ship both as artifacts of the same run.

That's a genuinely good fit. If the transform and the model drift apart you get silent
quality loss, and "these two artifacts were produced by one execution and are versioned
together" is the kind of guarantee an orchestrator exists to provide. SGT also applies to
**fine-tuning data**, not just inference — so the same pipeline can protect the training
corpus.

## If you want to build something today

Build the *concept*, honestly labeled. Take a small open model, add calibrated Gaussian
noise to its embedding sequence, and sweep the noise scale to plot the **privacy/utility
curve**: decoded-back-to-tokens becomes garbage while downstream task accuracy degrades
only slightly.

That curve is Protopia's entire pitch, and it's a nice `flyte.map` over noise scales with
the results in a `flyte.report`.

⚠️ **Be honest about what that is.** Real SGT learns a sequence-dependent transform and
defends an MI bound. Fixed Gaussian noise does neither. Your toy shows the **tradeoff
axis** — it does not show the **guarantee**, and the guarantee is the product.

## Status

Chris is working the Protopia relationship for a real track. Want it? Say so — it moves
this up the list.
