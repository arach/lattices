# Overview

`action` is a native-first macOS demo automation project.

It is aimed at a workflow where a human operator or an AI agent can:

- inspect an app, browser surface, or bounded region
- execute deterministic actions
- record raw capture plus structured runtime traces
- turn those traces into polished demo or promo outputs later

## What Exists Today

The current repo is early, but it already has a meaningful native core:

- a signed `Action.app` bundle
- a real AppKit launcher with menus and WebKit support
- a local `Action` agent runtime reachable over WebSocket
- native screenshot and recording commands
- permission and diagnostics wrappers for local development

The strongest proof point right now is native capture:

- screenshot flows work
- `ScreenCaptureKit` recording now works through a real app lifecycle path

## Current Architecture Direction

The project is deliberately split into two responsibilities:

- `Action.app` owns AppKit lifecycle, menus, WebKit, settings, and permission UX
- the local agent owns transport, automation-facing methods, and runtime orchestration

This split exists because UI lifecycle and automation lifecycle are not the same
problem on macOS. Earlier experiments showed that trying to make a command-style
runtime also own WebKit and recording behavior leads to brittle failures.

## Repository Shape

- [README.md](README.md): top-level project framing
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): deeper product and systems architecture
- [docs/VISION.md](docs/VISION.md): product intent and precedent learnings
- [native/engine](native/engine): Swift native engine, app host, local agent, and scripts
- [packages](packages): JS-side tooling and operator surfaces

## What Matters Most Right Now

At this stage, the most important technical goal is reliable native capture.

That means:

- real AppKit lifecycle correctness
- stable `ScreenCaptureKit` recording behavior
- clear artifacts and finished markers
- preserving a clean boundary between UI-owned behavior and agent-owned behavior
