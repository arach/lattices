# Security Policy

Lattices is a local-first macOS app and CLI. It controls windows, tmux sessions, workspace
automation, OCR indexing, voice commands, and a localhost daemon, so security reports are taken
seriously even when the issue requires local access.

## Supported Versions

Security fixes target the latest public release and `main`.

## Reporting a Vulnerability

Please do not open a public issue for a suspected vulnerability.

Email security reports to <arach@tchoupani.com> with:

- a concise description of the issue
- reproduction steps or a proof of concept
- affected version or commit
- expected impact
- any relevant logs, screenshots, or config snippets

You should receive an initial response within a few days. If the report is accepted, we will
coordinate a fix and disclosure timeline before publishing details.

## Scope

Good reports include:

- unexpected network exposure of local APIs
- unsafe handling of local credentials, tokens, or environment variables
- command execution paths reachable through untrusted input
- permission bypasses for window control, OCR, audio, or automation features
- crashes or hangs in global input handling that could degrade desktop use

Out of scope:

- issues requiring arbitrary local code execution without a privilege boundary
- social engineering
- denial of service through intentionally malformed local developer config, unless it affects the
  global input hook or startup recovery
