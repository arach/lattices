#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
PACK_PATH="${1:-${ACTION_TYPING_SOUND_PACK:-$HOME/Downloads/30755__grcekh__keyboard-typing.zip}}"
OUTPUT_DIR="${ACTION_TYPING_SOUNDS_DIR:-$HOME/Library/Application Support/Action/Typing}"
BUN_BIN="${BUN_BIN:-$HOME/.bun/bin/bun}"
FFMPEG_BIN="${FFMPEG_BIN:-$(command -v ffmpeg || true)}"

if [[ -z "$FFMPEG_BIN" && -x "$HOME/.local/bin/ffmpeg" ]]; then
  FFMPEG_BIN="$HOME/.local/bin/ffmpeg"
fi

if [[ ! -x "$BUN_BIN" ]]; then
  echo "bun was not found at $BUN_BIN" >&2
  exit 1
fi

if [[ -z "$FFMPEG_BIN" || ! -x "$FFMPEG_BIN" ]]; then
  echo "ffmpeg was not found. Set FFMPEG_BIN to install typing sounds." >&2
  exit 1
fi

if [[ ! -f "$PACK_PATH" ]]; then
  echo "Typing sound pack was not found at: $PACK_PATH" >&2
  echo "Pass a zip path, or set ACTION_TYPING_SOUND_PACK." >&2
  exit 1
fi

TMP_DIR=$(mktemp -d /tmp/action-typing-pack.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

unzip -q "$PACK_PATH" -d "$TMP_DIR"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/grcekh-key-*.wav(N) "$OUTPUT_DIR"/LICENSE.txt

"$BUN_BIN" - "$TMP_DIR" "$OUTPUT_DIR" "$FFMPEG_BIN" <<'BUN'
const fs = require("fs");
const path = require("path");
const { execFileSync, spawnSync } = require("child_process");

const [srcDir, outDir, ffmpeg] = process.argv.slice(2);
const sources = fs.readdirSync(srcDir)
  .filter((name) => /keyboard-typing-\d+-.+\.(mp3|m4a)$/i.test(name))
  .map((name) => {
    const match = name.match(/keyboard-typing-(\d+)-/i);
    return { name, index: Number(match?.[1] ?? 0), file: path.join(srcDir, name) };
  })
  .sort((a, b) => a.index - b.index);

if (sources.length !== 10) {
  throw new Error(`Expected 10 source tracks, found ${sources.length}`);
}

function decodePreview(file) {
  return execFileSync(ffmpeg, [
    "-hide_banner", "-loglevel", "error",
    "-ss", "0", "-t", "22",
    "-i", file,
    "-ac", "1", "-ar", "22050",
    "-f", "s16le", "pipe:1",
  ], { maxBuffer: 80 * 1024 * 1024 });
}

function findClipStart(file, sourceIndex) {
  const pcm = decodePreview(file);
  const sampleCount = Math.floor(pcm.length / 2);
  const sampleRate = 22050;
  const win = Math.round(sampleRate * 0.018);
  const hop = Math.round(sampleRate * 0.006);
  const values = [];

  for (let offset = Math.round(sampleRate * 0.45); offset + win < sampleCount; offset += hop) {
    let sum = 0;
    let peak = 0;
    for (let i = 0; i < win; i++) {
      const value = pcm.readInt16LE((offset + i) * 2) / 32768;
      const absolute = Math.abs(value);
      peak = Math.max(peak, absolute);
      sum += value * value;
    }
    const rms = Math.sqrt(sum / win);
    const time = offset / sampleRate;
    values.push({ time, score: rms * 0.78 + peak * 0.22 });
  }

  const sorted = values
    .filter((value) => value.time > 0.55 && value.time < 20.5)
    .sort((a, b) => b.score - a.score);
  const picked = [];
  for (const candidate of sorted) {
    if (picked.every((value) => Math.abs(value.time - candidate.time) > 0.22)) {
      picked.push(candidate);
    }
    if (picked.length >= 8) {
      break;
    }
  }

  const choice = picked[(sourceIndex - 1) % Math.max(1, picked.length)] ?? sorted[0];
  if (!choice) {
    throw new Error(`Could not detect key hit in ${file}`);
  }
  return Math.max(0, choice.time - 0.018);
}

for (const source of sources) {
  const start = findClipStart(source.file, source.index);
  const out = path.join(outDir, `grcekh-key-${String(source.index).padStart(2, "0")}.wav`);
  const filter = [
    "highpass=f=85",
    "lowpass=f=4300",
    "acompressor=threshold=-22dB:ratio=2.0:attack=4:release=58:makeup=1.5",
    "afade=t=in:st=0:d=0.004",
    "afade=t=out:st=0.118:d=0.032",
    "volume=0.72",
  ].join(",");
  const result = spawnSync(ffmpeg, [
    "-hide_banner", "-loglevel", "error", "-y",
    "-ss", start.toFixed(3),
    "-i", source.file,
    "-t", "0.150",
    "-ac", "1", "-ar", "44100",
    "-af", filter,
    "-c:a", "pcm_s16le",
    out,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${source.name}: ${result.stderr}`);
  }
  console.log(`${path.basename(out)} <- ${source.name} @ ${start.toFixed(3)}s`);
}

const readmePath = path.join(srcDir, "_readme_and_license.txt");
if (fs.existsSync(readmePath)) {
  fs.copyFileSync(readmePath, path.join(outDir, "LICENSE.txt"));
}
BUN

printf 'Installed typing sound medley: %s\n' "$OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -name 'grcekh-key-*.wav' | sort
