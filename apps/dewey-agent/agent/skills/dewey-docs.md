---
description: Use when the user asks to inspect, improve, regenerate, or explain Lattices agent-ready documentation.
---

Use the deterministic tools as the first step:

1. `collect_docs` for current docs, manifests, read order, and artifact paths.
2. `audit_agent_docs` for missing source or generated artifacts.
3. `read_doc_artifact` when you need the source text for a specific page.
4. `generate_agent_artifacts` only after the user asks to regenerate generated files.

Keep the model's role narrow: explain the docs system, identify gaps, propose edits, and call the generator. The source of truth remains the Lattices repo and `apps/site/scripts/agent-docs.mjs`.
