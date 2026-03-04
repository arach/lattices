# Quickstart — Design Critique

## Scores
| Criterion | Score | Notes |
|-----------|-------|-------|
| Heading Hierarchy | 5/5 | No duplicate h1. Frontmatter title renders as h1. Body uses numbered h2s (## 1. Install tmux, etc.) — perfect for a sequential guide. No skipped levels. |
| Information Density | 5/5 | Each step is compact: a code block, one or two sentences of context. No bloat, no starvation. The "What's next" links section is appropriately brief. |
| Component Usage | 4/5 | Code blocks are well-placed. The numbered headings act as implicit steps. However, the JSON config example in step 4 could benefit from a brief annotation (e.g., field explanations inline or a small table). |
| Visual Rhythm | 5/5 | Five steps of roughly equal visual weight. Code blocks provide natural breathing room. The alternation of prose and code is consistent throughout. |
| Reading Flow | 5/5 | Perfect linear progression: install dependency, install tool, use it, customize, add companion app. Each step builds on the last. Exit links at the bottom. |
| **Total** | **24/25** | |

## Structural Issues

- None. This is a model quickstart page.

## Component Opportunities

- Step 2 offers two install methods (npm, source). A **tabs component** (npm / source) could make this cleaner if the docs-site supports it.
- Step 4's JSON block is introduced but not annotated — a 2-3 row inline table or brief list explaining `ensure`, `panes`, and `size` would help first-time readers without forcing them to the config reference.
- Step 5 mentions **Cmd+Shift+M** — a `<kbd>` styled element would make keyboard shortcuts visually distinct.

## Recommendations

1. Add a minimal annotation (list or inline comments) for the `.lattices.json` fields shown in step 4 so the reader doesn't need to leave the page to understand them.
2. Consider a tabs component for the npm vs. source installation paths in step 2.
3. Use `<kbd>` styling for Cmd+Shift+M.

## Verdict: PASS
