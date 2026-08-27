# Review UX V1 (Agent Notes)

## Goal
Turn session review into a fast, reliable "agent note" workflow:

1. seek quickly
2. anchor feedback precisely (point/range/region)
3. write actionable instruction
4. save and revisit notes

This is not a social commenting UI. It is a structured note system for an AI agent.

## Interaction Model

### 1) Single Composer
- One explicit composer entrypoint: `+ Feedback`
- Composer has anchor mode tabs:
  - `Point`: click timeline to stamp a single time
  - `Range`: drag timeline to set in/out
  - `Region`: drag on video frame to select area
- Composer always shows current anchor summary and short mode instructions.

### 2) Timeline As Primary Control
- Timeline must always support click and drag seek.
- Anchor creation overlays on top of seek behavior, not instead of it.
- In range mode, drag previews the range before commit.
- Timeline markers represent saved notes and jump playback on click.

### 3) Frame Region Selection
- Region mode is explicit and visible.
- Drag on frame creates a highlighted area with clear border.
- Region remains visible after selection and after save when focused.

### 4) Notes Rail
- Composer and saved notes live in a dedicated "notes rail".
- Saved notes are scrollable and selectable.
- Selecting a saved note focuses timeline + playback + region context.

## State Rules

- `isComposingFeedback` gates anchor creation.
- `anchorMode` controls source of anchor input:
  - timeline click for point
  - timeline drag for range
  - frame drag for region
- `Save` requires non-empty instruction.
- `Clear Anchors` only clears draft anchors, not saved notes.

## Quality Bar

- No hidden interaction modes.
- Every click/drag should produce immediate visual response.
- No ambiguous labels like "marking" without visible result.
- Primary actions should be discoverable without documentation.

## Follow-up (V1.1)

- Keyboard controls:
  - `N` open composer
  - `1/2/3` switch anchor mode
  - `Esc` cancel region mode
  - `Cmd+Enter` save note
- Inline marker hover previews.
- Optional snap-to-nearest-marker and frame-accurate stepping.
