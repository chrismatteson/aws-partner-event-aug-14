# The corpus

Ten IRS forms. Used by [Module 10](../modules/10-llamaindex.md).

## Why IRS forms

Because they're **genuinely hard**, in the ways that matter for document parsing: dense
multi-column tables, checkbox grids, nested line-item numbering, footnotes that modify
cells three rows up. If a parser handles a 1040 Schedule properly, it will handle your
invoices.

They're also stable (these URLs don't move), public domain, and require no auth.

| File | What it is | Why it's here |
|---|---|---|
| `f1040.pdf` | Individual income tax return | The classic. Dense line-numbered table. |
| `fw2.pdf` | Wage and tax statement | Boxed grid layout — hostile to naive text extraction. |
| `f941.pdf` | Employer's quarterly return | Multi-page with running totals. |
| `f1099msc.pdf` | Miscellaneous income | Multi-copy, repeated layouts. |
| `f1120.pdf` | Corporate return | Long, deeply nested schedules. |
| `f1065.pdf` | Partnership return | Same, different structure. |
| `f8949.pdf` | Capital gains | A big transaction table. |
| `fw9.pdf` | Taxpayer ID request | Short and mostly prose — a useful contrast. |
| `f2848.pdf` | Power of attorney | Prose plus signature blocks. |
| `f4562.pdf` | Depreciation | Numeric tables with heavy footnoting. |

## Why they're committed rather than downloaded

Three reasons, all learned the hard way:

1. **Rate limits are global, not per-user.** arXiv and SEC EDGAR both throttle by source.
   Forty attendees downloading simultaneously from one venue IP is precisely the traffic
   shape those limits exist to stop — you'd all get throttled together, and it would look
   like your code was broken.
2. **Venue wifi.** Enough said.
3. **Everyone parses the same bytes**, so when someone's output differs, that's a real
   signal instead of a different input.

## Size and rate-limit math

Ten documents is a deliberate number, not a lazy one. LlamaParse's free tier allows
**20 requests/minute**, and each document costs roughly two calls (upload, then parse).
Ten docs is about a minute of wall clock. Fifty docs would be five minutes of pure
rate-limit waiting inside a 90-minute module — see
[Module 10](../modules/10-llamaindex.md) for the full arithmetic.

## Refreshing

```bash
for f in f1040 f1099msc f941 fw2 f1120 f8949 fw9 f1065 f2848 f4562; do
  curl -sS -f -A "your-contact-email" -o "$f.pdf" "https://www.irs.gov/pub/irs-pdf/$f.pdf"
done
```

Pattern: `f` = form, `p` = publication, `i` = instructions.
Index: <https://www.irs.gov/downloads/irs-pdf>
