# Setup — about 20 minutes

Mostly clicking. Do it before Module 01.

1. **[00 — Wire up Kiro Web](00-kiro-web.md)** — connect the repo, paste in your
   secrets, open the network allow-list, add the Flyte MCP, and connect to your devbox.
2. **[01 — Meet your devbox](01-your-devbox.md)** — what's actually running in your
   AWS account, and how to read the UI you'll live in all day.

## The two checkpoints that matter

Everything downstream assumes both of these passed. If you skip them, later modules
fail in ways that look like *your* bug but aren't.

- **[Checkpoint A](00-kiro-web.md#-checkpoint-a-kiro-can-reach-your-devbox)** — Kiro can
  reach your devbox.
- **[Checkpoint B](00-kiro-web.md#-checkpoint-b-the-mcp-is-live)** — Kiro can reach the
  Flyte MCP server.

Checkpoint B is the one people skip, and it's the one that quietly ruins the day. A
Kiro without the MCP doesn't error — it *invents* Flyte APIs that have never existed
and states them confidently. If Kiro starts writing `@workflow` or importing
`flytekit`, that's v1 code it made up, and it means B is broken.

**Stuck for more than 5 minutes? Grab a facilitator.** That's what we're here for.
