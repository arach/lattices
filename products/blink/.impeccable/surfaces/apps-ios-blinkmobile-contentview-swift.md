---
version: 1
slug: "apps-ios-blinkmobile-contentview-swift"
primary_target: "apps/ios/BlinkMobile/ContentView.swift"
related_targets: ["apps/ios/BlinkMobile/BlinkMobileModel.swift","apps/ios/BlinkMobile/BlinkMobileApp.swift"]
---

Scope: Blink's native iPhone/iPad companion. Mode: Operate.

Audience and job: one Blink user recalling the same Mac-authored notes away from
their desk. They pair to a nearby Mac, sync, filter by workspace, search, and
read from an offline cache.

Primary task: find and read a note quickly while understanding whether the view
is live or offline. The source content is exact frontmattered Markdown projected
into native summaries and reading views.

Direction: Index Tape. The app is a carbon copy of the desktop log: warm paper
in light mode, neutral graphite in dark mode, a continuous indexed machine rail,
full-bleed rules, square state marks, and explicit monospaced trust language.
No forest wash and no rounded library cards. The workspace is the large title;
the Blink mark controls scope. Compact search grows from the bottom rail into a
real SwiftUI field; regular width uses native sidebar search. Keep native
navigation, Dynamic Type, VoiceOver grouping, keyboard avoidance, sheets, and
SF Symbols. The system serif is reserved for reader titles. Signal blue marks
live state or selection; amber is degraded/stale only.

Constraints: read-only v1; no desktop panel metaphor on mobile; no plaintext LAN
transport; quarantined source files retain their last known-good cached note.
Device approval is explicit on the Mac, credentials are host-scoped inside an
end-to-end sealed channel, and access remains revocable from the Mac menu.

Unresolved: mobile editing/conflicts, attachments, and Tailscale or
managed-relay routes.
