# Remote engine

Action can drive another machine that runs a lattices host (LAT-013), such as
a Linux desktop running `lattices-host`. Runs, traces and artifacts stay on
this machine; the remote host does the observing and acting.

```sh
ACTION_REMOTE_HOST=archie bun packages/mcp/src/index.ts     # MCP server against archie
ACTION_REMOTE_HOST=archie:9400 ACTION_REMOTE_FPS=8 ...      # port and recording rate
```

`action.health` reports the host's platform and capabilities in
`diagnostics`. From there the usual tools work: `action.observe.snapshot`
(surface, screenshot, OCR on the host), `action.observe.ocr`,
`action.resolve.target` (by point, or by text through the host's fuzzy OCR
search), and `action.act.execute` (click, type, press-key, drag, scroll,
focus-window, open-app).

What stays native-only, with a clear error: `action.observe.ax` (Linux has
no accessibility tree here), `action.record.*` (guided sessions record
through the engine instead), the stage and backdrop overlays, and the
companion worker.

In code, `RemoteEngine` (`packages/runtime/src/remote.ts`) implements
`CaptureEngine` and `SurfaceEngine`; `remoteEngineFromEnv()` builds one from
the environment.
