# Configuration — Design Critique

## Scores
| Criterion | Score | Notes |
|-----------|-------|-------|
| Heading Hierarchy | 3/5 | No duplicate h1. But the page has 11 h2 sections and 6 h3 sections for a reference page — several h2s are thin (e.g., "Creating a config" is 3 lines, "Machine-readable output" could be an h3 under CLI). The "Layouts" section uses h3s for pane counts (### 2 panes, ### 3+ panes, ### 4 panes) which is appropriate, but "Recovery" also has h3s (### sync, ### restart) that repeat information from the CLI table above. |
| Information Density | 3/5 | Several sections are underfilled for their heading weight. "Creating a config" is just `lattices init` + one sentence. "Auto-detection" is a short numbered list that could be a callout. "Machine-readable output" has two thin subsections. The CLI commands table is excellent. The tile positions table is excellent. But the "Recovery" section repeats `sync` and `restart` details already present in the CLI table. |
| Component Usage | 4/5 | Good use of tables for config fields, CLI commands, tile positions, and exit codes. ASCII diagrams for layouts are effective. Code blocks are well-placed. The JSON examples are clear. |
| Visual Rhythm | 3/5 | The page alternates between dense reference tables and very thin sections. "Creating a config" (3 lines), "Auto-detection" (4 lines), and "Exit codes" (small table) feel like interstitial fragments between heavier blocks. The layout diagrams create nice visual breaks but the section after them ("Auto-detection") deflates. |
| Reading Flow | 3/5 | The page starts well (config format, fields, layouts) but loses coherence in the second half. After "CLI commands" the page continues with "Machine-readable output," "Exit codes," "Recovery," and "Tile positions" — these feel tacked on rather than part of a deliberate progression. A reader looking for tile positions has to scroll past recovery docs. |
| **Total** | **16/25** | |

## Structural Issues

1. **Too many h2s for a reference page**: 11 h2 sections fragments the page. Group related content under fewer top-level headings.
2. **Redundant recovery section**: The sync and restart details in "Recovery" duplicate what's in the CLI commands table. Either expand the recovery section with genuinely new information (error handling, examples) or remove it and let the CLI table be the single source.
3. **Thin sections**: "Creating a config" (3 lines) and "Auto-detection" (short list) don't warrant h2 headings. They could be folded into the main config section or presented as callouts.
4. **Tile positions at the bottom**: This important reference is buried after recovery docs. It deserves to be closer to the layout diagrams or in its own clearly-linked section.

## Component Opportunities

- **Callout/tip** for "Auto-detection" — this is a "good to know" aside, not a primary section.
- **Callout/note** for "Creating a config" — `lattices init` is a one-liner tip.
- **Grouped sub-nav**: The CLI commands, exit codes, and machine-readable output sections could be grouped under a single "CLI Reference" h2 with h3 subsections.
- **Tabs component** for "Minimal example" vs. "Full example" JSON blocks.

## Recommendations

1. **Consolidate thin sections**: Merge "Creating a config" and "Auto-detection" into the main `.lattices.json` section as callouts or brief paragraphs.
2. **Group CLI-related content**: Create a single "CLI Reference" h2 containing CLI commands table, machine-readable output, and exit codes as h3s.
3. **Remove or differentiate Recovery**: Either delete the recovery section (since the CLI table covers it) or add unique content like troubleshooting scenarios, error messages, and retry behavior.
4. **Move Tile positions** up near the Layouts section, since they're conceptually related to spatial arrangement.
5. **Reorder for reference scanning**: Config format -> Layouts -> Tile positions -> CLI reference -> Recovery/troubleshooting.

## Verdict: NEEDS_WORK
