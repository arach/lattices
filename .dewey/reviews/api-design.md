# Daemon API — Design Critique

## Scores
| Criterion | Score | Notes |
|-----------|-------|-------|
| Heading Hierarchy | 3/5 | No duplicate h1. But the page has 27 h3 entries (one per API method, plus client helpers, plus integration patterns). "Read methods" and "Write methods" at h2 are good groupings, but the sheer number of h3s makes the ToC enormous. "Events" at h2 with 3 h3s is fine. "Agent integration patterns" at h2 with 4 h3s is well-structured. |
| Information Density | 4/5 | Each method entry follows a consistent template (Params, Returns, Errors, Notes) which is excellent for reference. The content per method is appropriate — not too verbose, not too sparse. The "Agent integration patterns" section is genuinely valuable and well-filled. However, methods like `session.kill`, `session.detach`, and `group.kill` are near-identical in structure — a combined table could reduce repetition. |
| Component Usage | 4/5 | Excellent use of tables for params and return fields. JSON code blocks for request/response examples. The wire protocol section is well-structured with distinct Request/Response/Event subsections. Horizontal rules (`---`) between methods provide visual separation. |
| Visual Rhythm | 3/5 | The page is very long (~705 lines). The repetitive method entries (Params table -> Returns JSON block -> optional Errors/Notes) create a monotonous rhythm after the 5th or 6th method. The horizontal rules help but can't fully compensate for the structural repetition. The "Agent integration patterns" section at the end breaks the monotony with longer code examples. |
| Reading Flow | 4/5 | The progression is logical: Quick start -> Wire protocol -> Read methods -> Write methods -> Events -> Integration patterns. The quick start gets the reader to a working example in 3 steps, which is ideal for an API reference. The integration patterns at the end provide real-world context. However, a reader looking for a specific method must scroll through a very long page. |
| **Total** | **18/25** | |

## Structural Issues

1. **Extremely long page**: At ~705 lines, this is by far the longest documentation page. For an API reference this is somewhat expected, but the length combined with repetitive structure makes navigation challenging.
2. **27 h3 entries overwhelm the ToC**: The right-side Table of Contents becomes a scrolling list rather than a navigation aid. This defeats the purpose of the ToC.
3. **Simple methods repeat the same pattern**: Methods like `session.kill`, `session.detach`, `group.kill`, and `group.launch` have nearly identical structures (single param, returns `{ "ok": true }`). These could be grouped.
4. **No method index/summary table**: The reader has no quick overview of all 20 methods before diving into the details. The Overview page mentions "20 RPC methods" but the API page never lists them all in one place.

## Component Opportunities

- **Method index table** at the top: A summary table listing all 20 methods with one-line descriptions and anchor links. This gives the reader a map before the detail dive.
- **Collapsible/accordion** for individual method entries — expand to see params/returns, collapse to scan quickly.
- **Grouped tables** for simple write methods: `session.kill`, `session.detach`, `group.launch`, `group.kill` could share a single table showing method, required params, and description.
- **Callout/warning** for the security note (localhost-only binding) — this is important and currently buried mid-page on the App page, referenced here only by link.
- **Badge/tag** for method type (read vs. write) next to each h3 heading.

## Recommendations

1. **Add a method index table** immediately after the Quick start section. List all 20 methods with a one-line description and an anchor link. This is the single highest-impact improvement.
2. **Consolidate simple write methods**: Group methods with identical signatures (single string param, returns `{ "ok": true }`) into a shared table with per-method notes.
3. **Consider splitting**: The page could be split into "API Overview & Protocol" (quick start, wire protocol, client, events, integration) and "API Method Reference" (the 20 methods). This keeps the conceptual content scannable and the reference exhaustive.
4. **Add the security note** directly on this page rather than relying on readers finding it on the App page.

## Verdict: NEEDS_WORK
