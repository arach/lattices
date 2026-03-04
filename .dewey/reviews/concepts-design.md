# Concepts — Design Critique

## Scores
| Criterion | Score | Notes |
|-----------|-------|-------|
| Heading Hierarchy | 3/5 | No duplicate h1 (good). But the Glossary section uses h3s for each term (### Daemon, ### Session, etc.), creating 9 h3 entries under a single h2. This produces a very long ToC and makes the glossary visually dominant. Additionally, "Architecture" has nested h3s (### Four-layer stack, ### Session naming, ### Window discovery, ### Space switching, ### Ensure/prefill) that are fine individually but combined with the glossary h3s, the page has 14+ h3 entries — heavy for a concepts page. |
| Information Density | 3/5 | The glossary entries are well-written but the heading-per-term pattern creates excessive fragmentation. Several terms (Multiplexer, Sync, Ensure/Prefill) are 1-3 sentences — too thin for their own heading. The "How it works" section is a clean numbered list, but "What is lattices?" repeats information already on the Overview page. |
| Component Usage | 3/5 | The tmux shortcuts table at the bottom is good. The ASCII architecture diagram is effective. But the glossary would be better as a **definition list** (`<dl>/<dt>/<dd>`) or a styled table rather than 9 separate h3 headings. The "How it works" numbered list is correct. |
| Visual Rhythm | 2/5 | The page has a rhythm problem: the glossary occupies roughly 40% of the page as a rapid-fire sequence of small h3 sections (some just 2-3 lines). Then the architecture section is dense and technical. The contrast between many tiny sections and a few large ones creates an uneven reading cadence. |
| Reading Flow | 3/5 | The "What is lattices?" intro repeats the overview page, which may confuse readers who arrive from the sidebar nav wondering if they're on the right page. The glossary-first structure works for reference but makes the page feel like a dictionary rather than a conceptual guide. The "Agentic architecture" section at the end is excellent but may get lost after the long glossary. |
| **Total** | **14/25** | |

## Structural Issues

1. **Glossary fragmentation**: 9 h3 headings under "Glossary" is too many individual sections. Each becomes a ToC entry, cluttering the right-side navigation. Many terms are 1-3 sentences — below the threshold for their own heading.
2. **Redundant intro**: "What is lattices?" duplicates the Overview page's first paragraph almost verbatim.
3. **Heavy ToC**: With 14+ h3 entries, the Table of Contents sidebar becomes a long scrolling list that undermines scanability.
4. **Unbalanced sections**: Glossary terms average 3 lines each; Architecture subsections average 10-15 lines each. The visual weight is lopsided.

## Component Opportunities

- **Definition list** for the glossary: Replace h3 headings with a `<dl>` element or a styled two-column table (Term | Definition). This collapses the glossary into a single scannable block and removes 9 ToC entries.
- **Callout/tip** for the "What is lattices?" intro: If it must stay, make it a brief callout rather than a full section, or remove it entirely and let the page jump straight into the glossary.
- **Tabs or accordion** for glossary terms if the docs-site supports it — lets readers expand terms they need without visual overload.

## Recommendations

1. **Restructure the glossary** as a definition list or table, not individual h3 headings. This is the single highest-impact change for this page.
2. **Remove or collapse "What is lattices?"** — the Overview page already covers this. Replace with a single sentence or delete entirely.
3. **Reorder the page**: Lead with "Architecture" (the meatiest, most unique content), then "How it works" (the workflow), then "Glossary" (reference material). Conceptual pages should build understanding before providing reference.
4. **Consider splitting**: The page tries to be both a conceptual guide and a glossary. If the glossary grows, it could be its own page.

## Verdict: NEEDS_WORK
