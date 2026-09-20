---
target: HomeView.swift
total_score: 23
max_score: 40
na_heuristics:
p0_count: 0
p1_count: 3
timestamp: 2026-09-03T18-11-30Z
slug: apps-ios-sources-home-homeview-swift
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Real-time hardware telemetry is prominent, but conflicting status terms (`ACTIVE`, `idle`, `READY`, `ready`) across the top, card, and footer create cognitive friction; activity feed repeats stale identical events. |
| 2 | Match System / Real World | 3 | Uses natural hardware and workspace terminology (CPU/GPU/MEM/THM, windows, nearby hosts), but voice jargon ("summon on air") and unparsed window labels ("Preview · Talkie iPhone 17 Pro") lack context. |
| 3 | User Control and Freedom | 2 | Empty Scenes and Routines containers cannot be hidden, configured, or dismissed; persistent Cloud strip cannot be dismissed despite reporting zero activity. |
| 4 | Consistency and Standards | 2 | Deviates from native iOS HIG patterns: custom bordered containers instead of inset grouped lists, sub-11pt micro-labels, and nested interactive button targets inside a tappable card. |
| 5 | Error Prevention | 3 | Passive home monitoring surface prevents unintended destructive commands; host mic button has distinct hit styling. |
| 6 | Recognition Rather Than Recall | 2 | Empty sections state what is missing without explaining what scenes or routines do or how to create them; repetitive window logs bury actual recent user or agent commands. |
| 7 | Flexibility and Efficiency | 3 | Quick access to mic capture and full command deck right from the bottom bar; host card allows immediate jump into deck. |
| 8 | Aesthetic and Minimalist Design | 1 | Severe vertical real estate waste on compact phone screens: two non-actionable empty-state boxes, duplicate telemetry spam, redundant host name in 3 places, and zero-value cloud strip. |
| 9 | Error Recovery | 3 | Connection drops and offline states are safely indicated via status badges without crashing or locking the interface. |
| 10 | Help and Documentation | 2 | Settings gear is present, but no contextual hints exist to guide first-time pairing, scene creation, or routine automation. |
| **Total** | | **23/40** | **Acceptable (57.5%)** |

## Design Specificity Verdict

**Authored Core vs. Category-Interchangeable Bloat**

- **Visual Assessment**: The industrial dark console aesthetic (Dieter Rams / Teenage Engineering / Teenage Operator console) is undeniably distinct: the high-contrast vertical hardware gauges (CPU, GPU, MEM, THM), the monospace telemetry tokens, and the low-profile chassis styling give Lattices Companion a physical tool identity. However, on an iPhone screen (specifically iPhone 13 mini), the layout reveals its origin as an iPad-first "passive glanceable desk instrument." When squashed into compact portrait mode, the interface suffers from acute vertical crowding, unreadable 8–9pt typography, dead-end empty state boxes, and repetitive log flooding that betrays its bespoke craft.
- **Deterministic Scan**:
  - Swift Native target: AST scan for web rules skipped.
  - Native Inspection: Verified against iOS Human Interface Guidelines (44pt touch targets, 11pt type floor, Dynamic Type, and safe-area compliance).
- **Visual Evidence**: Analyzed from live on-device screenshot (`Image #1`, iPhone 13 mini, 721×1568 resolution).

## Overall Impression

Lattices Companion looks like a gorgeous piece of boutique audio/hardware equipment, but it currently behaves like an uncurated debug dashboard on compact iPhone screens. Half the viewport is eaten up by two non-actionable empty state cards ("no scenes saved yet", "no routines yet") and a spammy activity log repeating "36 desktop windows" 5 times in a row, while the host name and status are repeated three times in different places. Trimming the empty waste, deduplicating the feed, and establishing clear typographical hierarchy will turn this into a razor-sharp mobile remote.

## What's Working

1. **Physical Hardware Telemetry Gauges**: The 4 vertical bar gauges for CPU, GPU, MEM, and THM with proportional fills and top-aligned load numbers instantly evoke high-end rack-mounted audio gear and Teenage Engineering consoles.
2. **Compact Hardware Identity**: The Mac mini device glyph, the high-contrast active status dot, and the inline voice mic trigger make the primary target immediately identifiable.
3. **Dedicated Bottom Command Dock**: Docking the voice button and 2×2 grid deck trigger into a persistent bottom bar gives one-thumb access to primary mobile actions regardless of scroll position.

## Priority Issues

- **[P1] Empty-State Real Estate Waste (Scenes & Routines Dead Ends)**:
  - *What*: Two massive bordered cards take up more than 30% of the visible viewport solely to display "no scenes saved yet" and "no routines yet".
  - *Why it matters*: On a 5.4" phone display, pushing live recent activity and quick actions off-screen for two completely dead, non-interactive boxes creates immediate frustration and cognitive friction.
  - *Fix*: When empty, collapse Scenes and Routines into subtle inline rows with a `+ Create on Mac` hint, or hide them entirely (as the component's architecture originally envisioned) until scenes exist.
  - *Suggested command*: `/impeccable distill`

- **[P1] Activity Feed Polling Flood (Log Spam)**:
  - *What*: The Activity card renders 5 identical rows: `• AGENT 36 desktop windows` without timestamps or grouping.
  - *Why it matters*: High-frequency window polling noise completely drowns out meaningful agent tool actions, human commands, and errors.
  - *Fix*: Deduplicate consecutive identical state events in `HomeDataAdapter.agentFeed`. Collapse repeated window counts into an ambient badge or single state line ("36 windows · stable") with relative timestamps (`2m ago`).
  - *Suggested command*: `/impeccable clarify`

- **[P1] Status Dissonance & Redundant Chrome**:
  - *What*: The host name "Arach's Mac mini" appears in the top bar pill, in the machine card, and in the bottom status bar. Simultaneously, four different status tokens are displayed: `• ACTIVE` (card top), `• idle` (card bottom), `• READY` (footer left), and `• ready` (footer right).
  - *Why it matters*: Users cannot discern whether the machine is busy, idle, or ready, and why the same machine name is repeated across three navigation bars.
  - *Fix*: Remove the redundant machine selector pill from the top bar when only 1 machine is paired; unify daemon status and agent state in the bottom bar into a single coherent sentence (e.g., `Arach's Mac mini · idle`).
  - *Suggested command*: `/impeccable layout`

- **[P2] Sub-11pt Font Violations & Readability Floor**:
  - *What*: Subtitle headers (`no scenes saved · summon on air`, `multi-step · agent-assisted`, `12 agent`), telemetry labels (`CPU`, `GPU`, `MEM`, `THM`), and agent tags are rendered at 8pt to 10pt with faint opacity (`rgba(255,255,255,0.3)`).
  - *Why it matters*: Violates Apple iOS HIG reading floor (11pt minimum). On an iPhone 13 mini, glyphs under 2mm require squinting, especially under ambient light.
  - *Fix*: Elevate minimum functional text floor to 11pt, increase muted text contrast to pass WCAG AA, and adopt SF Pro / Dynamic Type semantic scales.
  - *Suggested command*: `/impeccable typeset`

- **[P2] Zero-State Cloud Strip Clutter**:
  - *What*: The `☁️ CLOUD · • 0 agents · • 0 builds queued` strip persistently floats above the bottom bar despite reporting zero active work.
  - *Why it matters*: Steals 36pt of precious vertical thumb space on mobile for zero information.
  - *Fix*: Enforce conditional rendering so the cloud strip automatically self-hides when `agentsRunning == 0 && buildsQueued == 0`.
  - *Suggested command*: `/impeccable distill`

## Persona Red Flags

- **Jordan (Confused First-Timer)**: Gets completely disoriented by the empty states and status terms. Jordan asks: *"Is my Mac ACTIVE, idle, or READY? What is a 'Scene', and how do I 'summon on air'? Why does it say '36 desktop windows' five times? Did something crash?"* Jordan cannot find any way to create a scene or routine on this screen.
- **Alex (Impatient Power User)**: Wants to glance at the phone beside the keyboard to see live agent progress. Instead, Alex has to scroll past two empty gray boxes and five duplicate window logs just to find the actual recent actions or trigger a routine.
- **Sam (Accessibility-Dependent User)**: Strains to read the 8pt and 9pt labels with `textFaint` opacity. Furthermore, the nested mic button inside the machine card creates hit-target ambiguity on small touchscreens, risking an accidental transition to the full Deck when aiming for voice.

## Minor Observations

- The diagonal arrow `↗` floats in the middle-bottom of the host card with no label; it looks like an orphaned link rather than a card-wide affordance.
- The `+ Add a host` slot displays `2 nearby` on the right, which is great discovery feedback, but the cell has no background fill to distinguish it from the section backdrop.
- The red/coral color fill (`#E8485C`) on the 89% CPU and 99% MEM gauges communicates critical system panic/overheating, even if high memory pressure is normal under macOS caching.

## Questions to Consider

- What if the Home screen on iPhone focused exclusively on the Host Card and live Activity feed, hiding Scenes and Routines until at least one preset is configured on the Mac?
- What if the bottom bar collapsed the separate Cloud Strip and daemon status into a single unified status pill (`● Connected · 1 Mac · Idle`) with one-tap expansion?
- Should the host card gauges use neutral amber/cream lighting, reserving coral/red strictly for thermal throttling (`THM > 85°C`) or process errors?
