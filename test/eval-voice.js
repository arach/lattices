#!/usr/bin/env node

// Voice command eval suite for Lattices PhraseMatcher
// Tests the full pipeline: text -> preamble strip -> phrase match -> slot resolution
// Requires the Lattices daemon to be running (ws://127.0.0.1:9399)
//
// Run: node test/eval-voice.js
// Flags:
//   --verbose    Show slot details for passing tests
//   --only=N     Run only test number N (1-based)
//   --section=X  Run only tests in section X (partial match)

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const { daemonCall, isDaemonRunning } = await import(
  resolve(__dirname, "../bin/daemon-client.js")
);

// ── CLI Flags ────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const verbose = argv.includes("--verbose");
const onlyIdx = argv.find((a) => a.startsWith("--only="))?.split("=")[1];
const sectionFilter = argv
  .find((a) => a.startsWith("--section="))
  ?.split("=")[1]
  ?.toLowerCase();

// ── Helpers ──────────────────────────────────────────────────────────

const PASS = "\x1b[32m PASS \x1b[0m";
const FAIL = "\x1b[31m FAIL \x1b[0m";
const SKIP = "\x1b[33m SKIP \x1b[0m";
const BUG = "\x1b[33m KNOWN\x1b[0m";

let passed = 0;
let failed = 0;
let knownBugs = 0;
const failures = [];

async function simulate(text) {
  return daemonCall("voice.simulate", { text, execute: false }, 5000);
}

function assert(label, result, expected, isKnownBug) {
  // expected: { intent, slots? } or { noMatch: true }
  if (expected.noMatch) {
    if (!result.parsed) {
      console.log(`${PASS} ${label}`);
      passed++;
    } else {
      const msg = `expected no match, got intent="${result.intent}"`;
      if (isKnownBug) {
        console.log(`${BUG} ${label} -- ${msg}`);
        knownBugs++;
      } else {
        console.log(`${FAIL} ${label} -- ${msg}`);
        failed++;
        failures.push({ label, msg });
      }
    }
    return;
  }

  if (!result.parsed) {
    const msg = `expected intent="${expected.intent}", got no match`;
    if (isKnownBug) {
      console.log(`${BUG} ${label} -- ${msg}`);
      knownBugs++;
    } else {
      console.log(`${FAIL} ${label} -- ${msg}`);
      failed++;
      failures.push({ label, msg });
    }
    return;
  }

  if (result.intent !== expected.intent) {
    const msg = `expected intent="${expected.intent}", got "${result.intent}"`;
    if (isKnownBug) {
      console.log(`${BUG} ${label} -- ${msg}`);
      knownBugs++;
    } else {
      console.log(`${FAIL} ${label} -- ${msg}`);
      failed++;
      failures.push({ label, msg });
    }
    return;
  }

  // Check slots if specified
  if (expected.slots) {
    for (const [key, val] of Object.entries(expected.slots)) {
      const actual = result.slots?.[key];
      if (actual !== val) {
        const msg = `slot "${key}": expected "${val}", got "${actual}"`;
        if (isKnownBug) {
          console.log(`${BUG} ${label} -- ${msg}`);
          knownBugs++;
        } else {
          console.log(`${FAIL} ${label} -- ${msg}`);
          failed++;
          failures.push({ label, msg });
        }
        return;
      }
    }
  }

  if (verbose && result.slots && Object.keys(result.slots).length > 0) {
    const slotStr = Object.entries(result.slots)
      .map(([k, v]) => `${k}="${v}"`)
      .join(", ");
    console.log(`${PASS} ${label} [${slotStr}]`);
  } else {
    console.log(`${PASS} ${label}`);
  }
  passed++;
}

// ── Test Definitions ─────────────────────────────────────────────────

const tests = [
  // ── Phrase matching basics ──
  { section: "Phrase matching basics" },
  { text: "find dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "search for lattices", expect: { intent: "search", slots: { query: "lattices" } } },
  { text: "tile left", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "tile top right", expect: { intent: "tile_window", slots: { position: "top-right" } } },
  { text: "maximize", expect: { intent: "tile_window", slots: { position: "maximize" } } },
  { text: "show safari", expect: { intent: "focus", slots: { app: "Safari" } } },
  { text: "focus chrome", expect: { intent: "focus", slots: { app: "Chrome" } } },
  { text: "open talkie", expect: { intent: "launch", slots: { project: "talkie" } } },
  { text: "kill my-session", expect: { intent: "kill", slots: { session: "my-session" } } },
  { text: "scan", expect: { intent: "scan" } },
  { text: "distribute", expect: { intent: "distribute" } },
  { text: "list windows", expect: { intent: "list_windows" } },
  { text: "list sessions", expect: { intent: "list_sessions" } },

  // ── More phrase variants ──
  { section: "Phrase variants" },
  { text: "look for dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "where is lattices", expect: { intent: "search", slots: { query: "lattices" } } },
  { text: "locate dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "snap left", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "move to the right", expect: { intent: "tile_window", slots: { position: "right" } } },
  { text: "full screen", expect: { intent: "tile_window", slots: { position: "maximize" } } },
  { text: "center it", expect: { intent: "tile_window", slots: { position: "center" } } },
  { text: "switch to safari", expect: { intent: "focus", slots: { app: "Safari" } } },
  { text: "launch talkie", expect: { intent: "launch", slots: { project: "talkie" } } },
  { text: "fire up talkie", expect: { intent: "launch", slots: { project: "talkie" } } },
  { text: "stop my-session", expect: { intent: "kill", slots: { session: "my-session" } } },
  { text: "rescan", expect: { intent: "scan" } },
  { text: "organize", expect: { intent: "distribute" } },
  { text: "tidy up", expect: { intent: "distribute" } },
  { text: "what's open", expect: { intent: "list_windows" } },
  { text: "what sessions are running", expect: { intent: "list_sessions" } },

  // ── Preamble stripping ──
  { section: "Preamble stripping" },
  { text: "Okay, find dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "Um, can you please search for lattices", expect: { intent: "search", slots: { query: "lattices" } } },
  { text: "Alright let's go ahead and tile left", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "Hey, show me safari", expect: { intent: "focus", slots: { app: "Safari" } } },
  { text: "Please find dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "Can you tile right", expect: { intent: "tile_window", slots: { position: "right" } } },
  { text: "Could you show chrome", expect: { intent: "focus", slots: { app: "Chrome" } } },
  { text: "I want to find lattices", expect: { intent: "search", slots: { query: "lattices" } } },
  { text: "Just scan", expect: { intent: "scan" } },
  { text: "So distribute", expect: { intent: "distribute" } },
  // Single-layer preambles that should work
  { text: "Okay find dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "Can you please find dewey", expect: { intent: "search", slots: { query: "dewey" } } },

  // ── Whisper punctuation artifacts ──
  { section: "Whisper punctuation handling" },
  { text: "Find all the Dewey windows.", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "Okay, tile left.", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "Can you show me Chrome?", expect: { intent: "focus", slots: { app: "Chrome" } } },
  { text: "Search for lattices!", expect: { intent: "search", slots: { query: "lattices" } } },
  { text: "Tile top right;", expect: { intent: "tile_window", slots: { position: "top-right" } } },
  { text: "Scan.", expect: { intent: "scan" } },
  // Whisper sometimes adds trailing period + space
  { text: "Find dewey. ", expect: { intent: "search", slots: { query: "dewey" } } },

  // ── cleanQuery noise stripping ──
  { section: "cleanQuery noise stripping" },
  { text: "find all the dewey windows", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "find all instances of lattices", expect: { intent: "search", slots: { query: "lattices" } } },
  { text: "show me all the chrome windows", expect: { intent: "search", slots: { query: "chrome" } } },
  { text: "where is dewey on my screen", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "find windows named dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  // Noise that should be stripped
  { text: "find all of the dewey windows", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "find dewey in the title", expect: { intent: "search", slots: { query: "dewey" } } },

  // ── Position resolution ──
  { section: "Position resolution" },
  { text: "tile top left", expect: { intent: "tile_window", slots: { position: "top-left" } } },
  { text: "tile top right", expect: { intent: "tile_window", slots: { position: "top-right" } } },
  { text: "tile bottom left", expect: { intent: "tile_window", slots: { position: "bottom-left" } } },
  { text: "tile bottom right", expect: { intent: "tile_window", slots: { position: "bottom-right" } } },
  { text: "tile left", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "tile right", expect: { intent: "tile_window", slots: { position: "right" } } },
  { text: "make it full screen", expect: { intent: "tile_window", slots: { position: "maximize" } } },
  { text: "snap to the center", expect: { intent: "tile_window", slots: { position: "center" } } },
  // Alternate names
  { text: "tile upper left", expect: { intent: "tile_window", slots: { position: "top-left" } } },
  { text: "tile lower right", expect: { intent: "tile_window", slots: { position: "bottom-right" } } },

  // ── Edge cases ──
  { section: "Edge cases" },
  { text: "scan the screen", expect: { intent: "scan" } },
  { text: "what's on my screen", expect: { intent: "scan" } },
  { text: "organize my windows", expect: { intent: "distribute" } },
  { text: "tidy up", expect: { intent: "distribute" } },
  { text: "read the screen", expect: { intent: "scan" } },
  { text: "what do i have open", expect: { intent: "list_windows" } },
  { text: "which projects are active", expect: { intent: "list_sessions" } },
  { text: "Um, okay, so like, can you please go ahead and find all the lattices windows on my screen?", expect: { intent: "search" } },
  // Reasonable single-preamble long utterances
  {
    text: "Can you please find all the lattices windows on my screen?",
    expect: { intent: "search", slots: { query: "lattices" } },
    label: "Long utterance with single preamble",
  },

  // ── Natural speech (how people actually talk) ──
  { section: "Natural speech" },
  // Vague / casual
  { text: "where'd my slack go", expect: { intent: "search", slots: { query: "slack" } } },
  { text: "I lost my terminal", expect: { intent: "search", slots: { query: "terminal" } } },
  { text: "where the hell is figma", expect: { intent: "search", slots: { query: "figma" } } },
  { text: "bring up my notes", expect: { intent: "search", slots: { query: "notes" } } },
  { text: "I need to see chrome", expect: { intent: "focus", slots: { app: "Chrome" } } },
  { text: "put this on the left side", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "move this over to the right", expect: { intent: "tile_window", slots: { position: "right" } } },
  { text: "can I get safari up", expect: { intent: "focus", slots: { app: "Safari" } } },
  { text: "throw it in the corner", expect: { noMatch: true } },
  { text: "just put it on the left", expect: { intent: "tile_window", slots: { position: "left" } } },
  // Whisper capitalization / casing weirdness
  { text: "Find DEWEY", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "TILE LEFT", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "Show Me Safari", expect: { intent: "focus", slots: { app: "Safari" } } },
  // Filler words and hedging
  { text: "uh can you like find dewey for me", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "yeah so like tile it to the left", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "hmm show me what's on the screen", expect: { intent: "scan" } },
  // Conversational wrappers
  { text: "I think I want to see all my dewey stuff", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "let's get everything organized", expect: { intent: "distribute" } },
  { text: "go ahead and clean up the windows", expect: { intent: "distribute" } },
  { text: "do a scan real quick", expect: { intent: "scan" } },
  { text: "fire up the lattices project", expect: { intent: "launch", slots: { project: "lattices" } } },
  // Indirect / implied
  { text: "get slack on screen", expect: { intent: "focus", slots: { app: "Slack" } } },
  { text: "pull up everything with dewey in it", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "what windows do I have", expect: { intent: "list_windows" } },
  { text: "show me my sessions", expect: { intent: "list_sessions" } },
  // Real Whisper transcription artifacts
  { text: "Okay. Find all the Dewey windows.", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "So, uh, tile left please.", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "I wanna see, like, where's Chrome at?", expect: { intent: "focus" } },
  { text: "Alright, let's do a quick scan.", expect: { intent: "scan" } },
  // Multi-word app/project names
  { text: "show me visual studio code", expect: { intent: "focus", slots: { app: "Visual Studio Code" } } },
  { text: "find google chrome", expect: { intent: "search", slots: { query: "google chrome" } } },
  { text: "open my notes app", expect: { intent: "launch", slots: { project: "notes" } } },
  // Ambiguous but should still work
  { text: "dewey", expect: { intent: "search", slots: { query: "dewey" } } },
  { text: "lattices windows", expect: { intent: "search", slots: { query: "lattices" } } },
  { text: "left half", expect: { intent: "tile_window", slots: { position: "left" } } },
  { text: "right side", expect: { intent: "tile_window", slots: { position: "right" } } },
  // Commands people would say naturally but aren't in templates
  { text: "close the dewey session", expect: { intent: "kill", slots: { session: "dewey" } } },
  { text: "shut everything down", expect: { noMatch: true } },
  { text: "give me a fresh scan", expect: { intent: "scan" } },
  { text: "refresh the screen text", expect: { intent: "scan" } },
  { text: "line everything up", expect: { intent: "distribute" } },

  // ── Help / meta ──
  { section: "Help and meta" },
  { text: "help", expect: { intent: "help" } },
  { text: "help me", expect: { intent: "help" } },
  { text: "what can I do", expect: { intent: "help" } },
  { text: "what can you do", expect: { intent: "help" } },
  { text: "how does this work", expect: { intent: "help" } },
  { text: "what can I say", expect: { intent: "help" } },
  { text: "what are my options", expect: { intent: "help" } },
  { text: "show me the commands", expect: { intent: "help" } },

  // ── Should NOT match (expect fallback) ──
  { section: "Should NOT match (fallback)" },
  { text: "what time is it", expect: { noMatch: true } },
  { text: "tell me a joke", expect: { noMatch: true } },
  { text: "how are you doing", expect: { noMatch: true } },
  { text: "the weather today", expect: { noMatch: true } },
  { text: "play some music", expect: { noMatch: true } },
  { text: "set a timer for five minutes", expect: { noMatch: true } },
];

// ── Run ──────────────────────────────────────────────────────────────

async function runVoiceTests() {
  console.log("\n=== Voice Command Eval Suite ===\n");

  const alive = await isDaemonRunning();
  if (!alive) {
    console.error(
      "Lattices daemon is not running. Start it with: node bin/lattices-app.js restart"
    );
    process.exit(1);
  }

  let currentSection = null;
  let testNum = 0;

  for (const test of tests) {
    if (test.section) {
      currentSection = test.section;
      if (!sectionFilter || currentSection.toLowerCase().includes(sectionFilter)) {
        console.log(`\n-- ${test.section} --`);
      }
      continue;
    }

    testNum++;

    // Filter by --only
    if (onlyIdx && testNum !== parseInt(onlyIdx)) continue;
    // Filter by --section
    if (sectionFilter && !currentSection?.toLowerCase().includes(sectionFilter)) continue;

    const label =
      test.label ||
      `"${test.text}" -> ${test.expect.noMatch ? "no match" : test.expect.intent}`;

    // Handle empty string edge case (daemon rejects empty text param)
    if (test.text === "") {
      // Expect the daemon to reject, treat as "no match"
      try {
        const result = await simulate(test.text);
        assert(label, result, test.expect, test.knownBug);
      } catch {
        // Daemon rejection of empty text = no match, which is correct
        if (test.expect.noMatch) {
          console.log(`${PASS} ${label} (daemon rejected empty text)`);
          passed++;
        } else {
          console.log(`${FAIL} ${label} -- daemon rejected empty text`);
          failed++;
          failures.push({ label, msg: "daemon rejected empty text" });
        }
      }
      continue;
    }

    try {
      const result = await simulate(test.text);
      assert(label, result, test.expect, test.knownBug);
    } catch (err) {
      console.log(`${FAIL} ${label} -- error: ${err.message}`);
      failed++;
      failures.push({ label, msg: err.message });
    }
  }
}

// ── Search API shape tests ───────────────────────────────────────────

async function runSearchApiTests() {
  if (sectionFilter && !"search api".includes(sectionFilter)) return;

  console.log("\n\n=== Search API Shape Tests ===\n");

  // Use windows.search (lighter weight, less likely to timeout)
  const queries = ["Safari", "Chrome", "terminal"];

  for (const query of queries) {
    const label = `windows.search("${query}") returns valid shape`;
    try {
      const result = await daemonCall(
        "windows.search",
        { query },
        5000
      );

      if (!Array.isArray(result)) {
        console.log(`${FAIL} ${label} -- expected array, got ${typeof result}`);
        failed++;
        failures.push({ label, msg: `not an array` });
        continue;
      }

      if (result.length > 0) {
        const first = result[0];
        const hasWid = "wid" in first;
        const hasApp = "app" in first;
        const hasTitle = "title" in first;
        if (hasWid && hasApp && hasTitle) {
          console.log(
            `${PASS} ${label} (${result.length} results, first: wid=${first.wid} app="${first.app}")`
          );
          passed++;
        } else {
          const missing = [
            !hasWid && "wid",
            !hasApp && "app",
            !hasTitle && "title",
          ].filter(Boolean);
          console.log(`${FAIL} ${label} -- missing fields: ${missing.join(", ")}`);
          failed++;
          failures.push({ label, msg: `missing fields: ${missing.join(", ")}` });
        }
      } else {
        console.log(
          `${PASS} ${label} (0 results -- no matching windows, shape ok)`
        );
        passed++;
      }
    } catch (err) {
      console.log(`${FAIL} ${label} -- error: ${err.message}`);
      failed++;
      failures.push({ label, msg: err.message });
    }
  }

  // Also test lattices.search (unified search) with a single query
  const unifiedLabel = `lattices.search("Safari") returns valid shape`;
  try {
    const result = await daemonCall(
      "lattices.search",
      { query: "Safari", mode: "quick" },
      5000
    );
    if (Array.isArray(result)) {
      console.log(
        `${PASS} ${unifiedLabel} (${result.length} results)`
      );
      passed++;
    } else {
      console.log(`${FAIL} ${unifiedLabel} -- expected array, got ${typeof result}`);
      failed++;
      failures.push({ label: unifiedLabel, msg: "not an array" });
    }
  } catch (err) {
    console.log(`${FAIL} ${unifiedLabel} -- error: ${err.message}`);
    failed++;
    failures.push({ label: unifiedLabel, msg: err.message });
  }
}

// ── Main ─────────────────────────────────────────────────────────────

async function main() {
  const start = Date.now();

  await runVoiceTests();
  await runSearchApiTests();

  const elapsed = ((Date.now() - start) / 1000).toFixed(1);
  const total = passed + failed + knownBugs;

  console.log("\n\n=== Summary ===\n");
  console.log(`  Total:   ${total}`);
  console.log(`  \x1b[32mPassed:  ${passed}\x1b[0m`);
  if (failed > 0) {
    console.log(`  \x1b[31mFailed:  ${failed}\x1b[0m`);
  } else {
    console.log(`  Failed:  0`);
  }
  if (knownBugs > 0) {
    console.log(`  \x1b[33mKnown:   ${knownBugs}\x1b[0m (expected failures, tracked bugs)`);
  }
  if (failures.length > 0) {
    console.log("\n  Unexpected failures:");
    for (const f of failures) {
      console.log(`    - ${f.label}`);
      console.log(`      ${f.msg}`);
    }
  }
  console.log(`\n  Elapsed: ${elapsed}s\n`);

  process.exit(failed > 0 ? 1 : 0);
}

main();
