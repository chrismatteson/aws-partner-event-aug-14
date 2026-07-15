# 21 — CloudZero: what does one agent run actually cost?

> 🚧 **Stub — not a hands-on module yet.** Read it as background; there's nothing to run.
> Of the three stubs this is the **closest to buildable** — see below.

## The problem

Your AI bill is a number. It is not an answer.

"EC2: $40k, Bedrock: $12k" tells you nothing you can act on. The questions that matter
are **per-unit**: cost per customer, per feature, per inference, per 1,000 tokens, per
eval sweep. Without those you can't price the product, can't find the customer who's
underwater, can't tell whether last week's prompt change made you money or cost you money.

The standard blocker is tagging. Allocation needs perfect tags; nobody has perfect tags;
so the project dies.

## CloudZero's answer

**CostFormation** — a YAML rule language that allocates spend to Elements from billing
line items *plus* other sources, without requiring perfect tags. When tags don't reach,
it allocates **proportionally**, by **even split**, or by **telemetry you send it**.

That last one is the hook.

## Why Flyte is unusually well-suited to this

Here's the thing that makes this worth a track: **most infrastructure has to guess at
allocation. Flyte doesn't have to.**

Every task pod already carries `project`, `domain`, `workflow`, and `execution-id`. Those
aren't tags someone remembered to add — they're intrinsic to how Flyte identifies work.
The allocation dimensions are already there, for free, on every pod, always.

So "cost per workflow run / per agent run / per eval sweep" isn't a tagging project. It's
a join.

## Why it's a stub

**No self-serve signup.** The pricing page publishes no prices; the CTA is "Request a
custom price quote." A 14-day trial exists but only for sales-qualified accounts. You
can't hand 40 attendees a login.

## But the interfaces are public — and good

This is what makes it the most buildable stub. CloudZero's API docs are open and precise:

- **Unit Metric Telemetry** — `POST /unit-cost/v1/telemetry/metric/{metric_name}/sum`:
  ```json
  {"records": [{
    "timestamp": "2026-08-14T00:00:00",
    "value": "12345",
    "associated_cost": {"custom:Project": "...", "custom:Workflow": "..."}
  }]}
  ```
  Daily granularity, **max 5 dimensions per stream**, 100 records/sec.
- **AnyCost Stream** — `POST /v2/connections/billing/anycost/{id}/billing_drops`, taking
  Common Bill Format (minimum: `cost/cost` + `time/usage_start`). There's a working
  [reference adaptor](https://github.com/Cloudzero/cloudzero-anycost-example).
- Auth: API key in a bare `Authorization` header — **no `Bearer` prefix**.
- **[`cloudzero-agent`](https://github.com/Cloudzero/cloudzero-agent) is Apache-2.0** and
  emits `cloudzero_pod_labels`. Label patterns are regex-configurable, and labels are on
  by default (annotations aren't). **Flyte's pod labels would flow straight into it.**

## What the real track probably looks like

A task reads its own pod metadata, multiplies wall-clock by node instance price, and
emits a CBF-shaped record — POSTed at a local mock of the CloudZero endpoint. You'd
demo the exact payload CloudZero accepts, print a cost-per-execution table, and say
honestly: *swap the base URL and add a key, and this is production.*

The lesson is better than a dashboard tour, because the constraints teach something:
**daily granularity** and the **5-dimension cap** are precisely why per-execution
attribution is hard. `execution-id` is high-cardinality and will fight that cap. That
tension is the real content.

## Status

Needs a CloudZero conversation about a demo tenant, or a decision to ship the
mock-endpoint version. The Apache-2.0 agent means there's a legitimate OSS path here that
the other two stubs don't have — this is the one to build next.
