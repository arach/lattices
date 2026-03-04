# Workspace Layers & Tab Groups — Design Critique

## Scores
| Criterion | Score | Notes |
|-----------|-------|-------|
| Heading Hierarchy | 4/5 | No duplicate h1. The page has two major h2s (Tab Groups, Layers) with well-organized h3 subsections. However, "Layout examples" at h2 level feels like it belongs under "Layers" as an h3, since the examples are all layer project configurations. "Tips" as a final h2 is appropriate. |
| Information Density | 4/5 | Sections are generally well-filled. The JSON config examples are clear and progressively complex. The "Menu bar app" h3 under Tab Groups is slightly thin — it's a feature description list that could be tighter. The "Layout examples" section has 4 JSON blocks that are useful but repetitive in structure. |
| Component Usage | 4/5 | Good use of tables for fields and commands. JSON code blocks are well-placed. The ASCII layer bar diagram is a nice touch. The "Switching layers" section uses a table for the three methods, which works well. The tips section as a bullet list is appropriate. |
| Visual Rhythm | 3/5 | The page is long and has two distinct halves (Tab Groups, Layers) of roughly equal weight. Within each half, the rhythm is good. But the "Layout examples" section at the bottom adds four consecutive JSON blocks with minimal prose between them — this creates a code-heavy tail that's visually monotonous. The overall page length (316 lines) is pushing the limit for a single page. |
| Reading Flow | 4/5 | The two-concept structure (Tab Groups first, Layers second) is logical since layers can reference groups. The intro paragraph clearly states what the page covers. However, the "Layout examples" section at the end feels detached from the Layers section it belongs to — a reader might not realize these are layer-specific examples. |
| **Total** | **19/25** | |

## Structural Issues

1. **"Layout examples" should be under Layers**: These are all examples of layer project configurations, not tab group examples. Making it an h3 under "Layers" (### Examples) would clarify the relationship.
2. **Page length**: At 316 lines, this is the second-longest doc page. The two concepts (tab groups and layers) are distinct enough that they could be separate pages if needed, though combining them is defensible since they share `workspace.json`.
3. **Repetitive JSON examples**: The four layout examples at the bottom show minor variations of the same structure. They could be condensed into one annotated example with callout notes for variations.

## Component Opportunities

- **Tabs component** for the layout examples — single project / two-project / group+project / four quadrants as selectable tabs.
- **Callout/tip** for the relationship between groups and layers — the "Using groups in layers" section is a key integration point that deserves visual emphasis.
- **Diagram** for the tmux mapping (1 group = 1 session, 1 tab = 1 window) — the text description is clear but a visual would reinforce understanding.

## Recommendations

1. **Move "Layout examples" under Layers** as an h3 subsection.
2. **Consolidate layout examples** using a tabs component or reduce to 2 representative examples with inline annotations for the others.
3. **Add a visual diagram** for the tab group -> tmux session mapping.
4. **Consider splitting** if the page grows further — Tab Groups and Layers are distinct enough for separate pages.

## Verdict: PASS
(Borderline — the structural issues are real but the content quality is high enough to pass.)
