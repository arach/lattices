# Voice Fallback Resolver — Prompt

Voice command resolver. Whisper transcript (may have typos): "{{transcript}}"

## Available intents

{{intent_catalog}}

## Current windows

{{window_list}}

## Instructions

Return ONLY a JSON object like:

```json
{"intent": "search", "slots": {"query": "dewey"}, "reasoning": "user wants to find dewey windows"}
```

- For search, extract the key term.
- Use window names from the list when relevant.
- If unclear, use intent "unknown".
