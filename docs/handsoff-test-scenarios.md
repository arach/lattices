# Hands-Off Mode — Test Scenarios

Press Ctrl+Cmd+M, say the phrase, press Ctrl+Cmd+M again. Check the result.

## 1. Basic awareness

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 1.1 | "What's the frontmost window?" | Names the app + project/title, no wid | Correct window? No numbers? |
| 1.2 | "How many monitors do I have?" | Correct count + sizes | Matches reality? |
| 1.3 | "What terminals do I have open?" | Lists terminals with projects/cwds | Does it know the projects? |
| 1.4 | "Which ones are running Claude Code?" | Lists only Claude terminals + their projects | Correct? Uses hasClaude? |
| 1.5 | "What's on my second monitor?" | Describes windows on the non-main display | Correct display? |

## 2. Simple tiling

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 2.1 | "Tile Chrome left" | Chrome moves to left half | Did it move? Spoken confirmation? |
| 2.2 | "Put iTerm on the right" | iTerm moves to right half | Correct window? |
| 2.3 | "Maximize this window" | Frontmost window maximizes | Right window? |
| 2.4 | "Center the Finder window" | Finder centers | Correct? |

## 3. Multi-window layouts

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 3.1 | "Split Chrome and iTerm" | Chrome left, iTerm right | Both move? Spoken narration? |
| 3.2 | "Put everything in a grid" | distribute intent fires | Windows arrange? |
| 3.3 | "Thirds with Chrome, iTerm, and Finder" | Three apps in left/center/right thirds | Correct apps + positions? |
| 3.4 | "Quadrants" | Four windows in corners | Reasonable choices? |

## 4. Focus + switching

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 4.1 | "Focus on Slack" | Slack comes to front | Did it switch? |
| 4.2 | "Switch to Chrome" | Chrome comes to front | Correct? |
| 4.3 | "Go to the lattices terminal" | Focuses the iTerm in ~/dev/lattices | Right terminal? |
| 4.4 | "Show me the Hudson Claude Code" | Focuses iTerm with hasClaude + cwd hudson | Correct? |

## 5. Conversational context

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 5.1 | "Tile Chrome left" then "Now put iTerm on the right" | Two separate turns, both work | Context from turn 1 used? |
| 5.2 | "Tile Chrome left" then "Swap them" | Chrome right, iTerm left | Understood "them"? |
| 5.3 | "What terminals do I have?" then "Organize those" | Lists, then distributes the terminals | Connected the turns? |
| 5.4 | "Put it back" (after any tiling) | Reverses last action | Worked? (may not be supported yet) |

## 6. Intelligence

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 6.1 | "Set up for coding" | Intelligent layout based on visible apps | Reasonable? Explained reasoning? |
| 6.2 | "I'm going to do a code review" | Suggests/applies review layout | Smart choice? |
| 6.3 | "Clean up my desktop" | Distributes or suggests organization | Actionable? |
| 6.4 | "Too many windows, simplify" | Suggests hiding some, focuses key ones | Reasonable? |

## 7. Error handling

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 7.1 | "Focus on Firefox" | "I don't see Firefox. You have Chrome and Safari." | Honest? Names real apps? |
| 7.2 | "Tile the Photoshop window" | "Photoshop isn't open right now." | No hallucination? |
| 7.3 | (mumble something unclear) | "I didn't catch that. Can you say it again?" | Graceful? |

## 8. Actions actually execute

| # | Say | Expected | Check |
|---|-----|----------|-------|
| 8.1 | "Distribute my windows" | spoken + distribute action | Actions array not empty? |
| 8.2 | "Organize my terminals" | spoken + distribute or tile actions | Actions actually fire? |
| 8.3 | Any action command | Hear narration BEFORE windows move | Sequence correct? |

## Scoring

For each test:
- ✅ Works correctly
- ⚠️ Partially works (note what's wrong)
- ❌ Broken (note error)
- 🔇 No audio feedback

Track in a copy of this file or in the terminal.
