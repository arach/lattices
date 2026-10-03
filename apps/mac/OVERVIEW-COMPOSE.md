# Overview layer composition

Branch: feat/layers-compose, based on origin/main e9d70400.

The window Layer menu now offers Add to, removable memberships (or a disabled
rule-held explanation), and New layer with this window. The multi-selection
footer offers New layer from N windows and, with one layer scoped, Add N to it.
A staged sheet names the layer and picks Left/Middle/Right/Full slots. The preview
uses LayerLayout.frames; the exact preview boxes are encoded as explicit grid
tiles. Only Create saves them; it never activates or arranges the layer.

Default lanes use AppTypeClassifier and LayerLayout.lane. Empty neighboring
lanes are reserved for explicit Left/Middle/Right picks. Full fills the display
and may overlap other slots. Off-desktop windows are kept in membership.

After create/add, shared layer selection follows the destination and Overview
shows a one-line confirmation. Remove uses the existing removal feasibility
calculation; no editing code was duplicated.

## Validation

441 Swift tests executed, 13 skipped, zero failures. Three new fixture-only composition tests plus two render tests
 cover terminal + Chrome lane geometry, off-desktop pinned membership,
slot/preview consistency, defaults and deduplication. No real layer was created,
added, removed or edited during development.

Unrelated bundle edits were preserved in stash
4ee5bdd30acbf851eac05e9784301f92499bc83e
(On feat/layers-act: Preserve coordinator bundle edits before layers-compose).
They are not part of this branch.

## User test

1. Open Overview and select All windows in the left index.
2. Open the window list with the panel toggle.
3. Click the Ghostty window, then Command-click the Chrome window.
4. In the selection footer, click New layer from 2 windows.
5. Name it Chrome + terminal. Confirm Ghostty = Left and Chrome = Right.
6. Click Create. This saves membership only; nothing moves.
7. Select the new layer in Layers and use Gather separately when ready.

For one window, select it, open Layer, then Add to > a layer, or
New layer with this window. Cancel dismisses the sheet without saving.


## Evidence and live limits

- compose-layer-menu.png: live dev app, a Chrome window on a last-known desktop;
  Add to, Remove from and New layer are visible. The menu was dismissed.
- compose-multi-footer.png and compose-new-layer-sheet.png: **fixture renders**,
  not screenshots of the user's real selection. They use Ghostty + Chrome and
  exercise the same native views; render Create callbacks fail the test if run.
- Direct event-posting permission is absent for this shell; daemon modifier
  automation did not produce a reliable multi-selection. No permissions changed.
  Real Command-click, multi-window sheet opening and Cancel remain for user
  acceptance. No live Create/Add/Remove, Gather or layout action was run.
- Release build passed (229.91s); dev app installed/relaunched from this worktree.
  The release app was not touched.
- workspace.json SHA-256 and mtime_ns unchanged from the pre-launch baseline:
  08371da3319997e03e858a71a55a736e77f421403078d8eca252082a728a3edc;
  1790863638274089681.
- Logs: /tmp/lattices-editor-slice-1/compose-final-tests.log,
  compose-release.log and compose-install.log.
