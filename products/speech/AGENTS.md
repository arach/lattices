# Speech

Speech is a separate macOS app. It owns synthesis requests, queue state, audio
playback, playback HUD, preferences, and its authenticated local RPC server.
Lattices is a client. Never transfer a Speech process handle or queue ownership
to Lattices, and never stop either app while quitting the other.

Reuse HudsonUIAudio and Vox providers. Keep existing credential service
`dev.lattices.app.voice`; do not copy credential values into preferences or logs.
Source provenance is recorded in SOURCE-PROVENANCE.json. The source checkout is
an active snapshot and must remain untouched.

Build/test with `swift test --package-path products/speech`. Remote Hudson and Vox defaults contain the shared speech changes.
Set SPEECH_HUDSON_PATH only for an explicit local dependency experiment.
Set SPEECH_VOX_PATH and HUDSON_VOX_PATH to the same Vox checkout when testing
unpublished Vox changes. Do not publish, install, or launch this app implicitly.
