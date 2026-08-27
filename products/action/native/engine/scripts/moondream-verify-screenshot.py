#!/usr/bin/env python3

import json
import os
import platform
import sys
import time
from pathlib import Path

import torch
from PIL import Image
from transformers import AutoModelForCausalLM, AutoTokenizer


DEFAULT_QUESTION = (
    "Look at this screenshot. Answer compact JSON with keys rendered, "
    "prompt_visible, image_grid_visible, and description. rendered should be "
    "true if a Midjourney result grid or finished image cards are visible."
)


def pick_device() -> str:
    requested = os.environ.get("MOONDREAM_DEVICE")
    if requested:
        return requested
    if torch.backends.mps.is_available():
        return "mps"
    if torch.cuda.is_available():
        return "cuda"
    return "cpu"


def parse_answer(answer: str) -> dict:
    cleaned = answer.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()
    try:
        parsed = json.loads(cleaned)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    lower = answer.lower()
    return {
        "rendered": "\"rendered\": true" in lower or "rendered: true" in lower,
        "prompt_visible": "prompt" in lower and "visible" in lower,
        "image_grid_visible": "grid" in lower or "image card" in lower or "result" in lower,
        "description": answer[:500],
    }


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"available": False, "error": "usage: moondream-verify-screenshot.py IMAGE [PROMPT]"}))
        return 2

    image_path = Path(sys.argv[1])
    prompt = sys.argv[2] if len(sys.argv) > 2 else ""
    if not image_path.exists():
        print(json.dumps({"available": False, "error": f"image not found: {image_path}"}))
        return 1

    question = os.environ.get("MOONDREAM_PROMPT")
    if not question:
        question = DEFAULT_QUESTION
        if prompt:
            question += f" The submitted prompt begins: {prompt[:180]}"

    model_id = os.environ.get("MOONDREAM_MODEL", "vikhyatk/moondream2")
    revision = os.environ.get("MOONDREAM_REVISION")
    max_tokens = int(os.environ.get("MOONDREAM_MAX_TOKENS", "320"))
    device = pick_device()

    load_started = time.perf_counter()
    load_kwargs = {"trust_remote_code": True, "low_cpu_mem_usage": True}
    if revision:
        load_kwargs["revision"] = revision
    load_kwargs["torch_dtype"] = torch.float16 if device in {"mps", "cuda"} else torch.float32
    model = AutoModelForCausalLM.from_pretrained(model_id, **load_kwargs)
    tokenizer = AutoTokenizer.from_pretrained(model_id, revision=revision if revision else None)
    model.eval()
    model.to(device)
    loaded = time.perf_counter()

    image = Image.open(image_path).convert("RGB")
    with torch.inference_mode():
        encoded = model.encode_image(image)
        answer = model.query(
            encoded,
            question,
            settings={"temperature": 0.0, "max_tokens": max_tokens},
        )["answer"].strip()
    finished = time.perf_counter()

    parsed = parse_answer(answer)
    rendered = bool(parsed.get("rendered")) and (
        bool(parsed.get("image_grid_visible")) or bool(parsed.get("prompt_visible"))
    )
    print(json.dumps({
        "available": True,
        "rendered": rendered,
        "parsed": parsed,
        "answer": answer,
        "image": str(image_path),
        "model": model_id,
        "device": device,
        "python": platform.python_version(),
        "timing_ms": {
            "load": round((loaded - load_started) * 1000),
            "query": round((finished - loaded) * 1000),
            "total": round((finished - load_started) * 1000),
        },
    }, indent=2))
    return 0 if rendered else 1


if __name__ == "__main__":
    raise SystemExit(main())
