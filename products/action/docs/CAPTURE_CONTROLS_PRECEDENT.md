# Capture Controls Precedent

## Keep

- a countdown that is obvious before capture starts
- controls that stay reachable while the take is live
- runtime-owned truth for recording state and interruption

## Avoid

- a HUD that shows buttons without a real control path behind them
- fake pause states when native capture is not actually paused
- interruption paths that leave recording hanging without a stop marker

## Adapt

- use the native stage HUD as the immediate operator surface
- keep the control channel file-based so the overlay and runner stay loosely coupled
- treat interrupt as a clean stop/cancel path instead of pretending the take can be paused safely

## Decision

- the guided native session will surface countdown skip/cancel before capture starts
- the live take will surface an interrupt control that stops recording cleanly
- cancelled runs will report cancellation explicitly instead of pretending they completed

## Reference Weight

Blend of `vif` product feel and `stage` runtime-boundary discipline.
