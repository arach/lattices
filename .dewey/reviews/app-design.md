# Menu Bar App — Design Critique

## Scores
| Criterion | Score | Notes |
|-----------|-------|-------|
| Heading Hierarchy | 3/5 | No duplicate h1 (good). But the page has 11 h2s and 9 h3s — an unusually high count. The "Command palette" section has 5 h3 subsections (Project, Window, Tab group, Layer, App commands), each containing a table. "Settings" has 3 h3s (General, Shortcuts, Docs). "Daemon" has 3 h3s. The sheer volume makes the ToC unwieldy. |
| Information Density | 4/5 | Most sections have substantive content. The command palette tables are valuable reference material. Settings is well-organized. However, "Diagnostics" at the bottom is a single paragraph (2 sentences) — too thin for an h2. "Supported terminals" could be a callout or note rather than a full section. |
| Component Usage | 4/5 | Excellent use of tables throughout — command palette tables, settings table, shortcuts table, supported terminals matrix. Code blocks for installation and daemon usage. The terminal support matrix with yes/activate/frontmost distinctions is well-designed. |
| Visual Rhythm | 3/5 | The command palette section dominates the first third of the page with five consecutive tables, which creates a wall-of-tables effect. Then the page transitions to prose-heavy sections (Project discovery, Session management), then back to tables (Settings, Terminals). The alternation isn't deliberate — it just happens. "Diagnostics" at the end is a single paragraph that trails off. |
| Reading Flow | 3/5 | The page covers a lot of ground and reads more like a reference manual than a guide. Installation -> Command palette -> Project discovery -> Session management -> Tiling -> Space nav -> Settings -> Terminals -> Daemon -> Diagnostics. There's no clear "most important thing first" ordering. A reader who just wants to use the app gets the same treatment as someone debugging permissions. |
| **Total** | **17/25** | |

## Structural Issues

1. **Wall of tables in command palette**: Five consecutive command palette tables (Project, Window, Tab group, Layer, App commands) create visual fatigue. Consider collapsing them or using tabs/accordion.
2. **Too many h2s (11)**: The page tries to cover everything about the app on one page. "Diagnostics" (2 sentences), "Daemon" (which is also covered on the API page), and "Supported terminals" could be consolidated.
3. **Daemon section duplicates API page**: The daemon description here overlaps with the API page's introduction. This creates maintenance burden and potential inconsistency.
4. **Trailing single-paragraph section**: "Diagnostics" as the last section feels like an afterthought.

## Component Opportunities

- **Tabs or accordion** for the command palette subsections — let users expand the command category they need.
- **Callout/tip** for Diagnostics — "To debug permission issues, open the Diagnostics panel from the command palette."
- **Callout/warning** for permissions — the Screen Recording and Accessibility permissions note in "Space navigation" is important enough to warrant a styled warning callout.
- **Link card** for the Daemon section — instead of duplicating daemon info, link to the API page with a brief summary card.

## Recommendations

1. **Collapse the command palette tables**: Either use a tabs component or reduce to two tables (one for project/window commands, one for app/layer/group commands).
2. **Extract or link the Daemon section**: Keep a 2-sentence summary with a prominent link to the API page. Remove the duplicated code examples.
3. **Promote the permissions note**: The Screen Recording and Accessibility requirements buried in "Space navigation" are critical setup information. Move to a top-level callout near Installation.
4. **Merge Diagnostics** into Settings or make it a callout.
5. **Add a "What you'll need" or "Permissions" section** near the top, since the app requires specific macOS permissions to function fully.

## Verdict: NEEDS_WORK
