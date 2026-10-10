# Linux host command socket — October 9, 2026

Item 1: command queries, dialect detection, dispatch batches and compositor exec
now use socket1 directly. Socket2 remains the event transport. No compositor
plugin, system configuration change, input injection or live-host restart.

## Measurements

Same Omarchy / Hyprland 0.56 machine, Bun 1.4.2, baseline origin/main
6f6892d8. Test host on **127.0.0.1:19499**, with no companion bridge.
End-to-end WebSocket windows.list: 100 calls per burst, 4 command queries per
call, 10 warm-up calls, 5 rounds. Same benchmark script before and after.

| Burst | Before median | After median | Speedup |
| --- | ---: | ---: | ---: |
| Sequential 100 calls | 434.44 ms | 28.69 ms | 15.14× |
| 100 calls, concurrency 2 | 287.29 ms | 19.36 ms | 14.84× |

Raw samples: host-linux-socket-before.json, host-linux-socket-after.json
in this directory. Reproduce with
bun packages/host-linux/scripts/benchmark.ts 19499 on the relevant revision.
Reads only: no window/monitor/workspace/input mutations.

## Choices and boundaries

- One Unix connection per request. Hyprland closes socket1 after each reply,
  so pooling a persistent socket would not implement its protocol.
- JSON uses j/, dispatch uses /dispatch, batches use [[BATCH]].
- 10-second request deadline and 64-MiB response ceiling match the old exec
  helper. Read to EOF, including multichunk/UTF-8 replies; never retry a
  potentially executed dispatch.
- Keep the existing Lua/legacy operation spellings and public method/schema
  definitions. The harmless dialect probe is cached per compositor socket.
- Batch success means **all dispatcher replies are ok**, otherwise the API
  reports errors. An incomplete/empty reply is also an error.

Important clarification: Hyprland itself does **not** provide rollback/atomic
transactions for batches. Earlier operations may execute before a later error.
This was also true of hyprctl --batch; preserving behavior cannot promise
physical all-or-nothing. See the compositor's
[dispatchBatch implementation](https://github.com/hyprwm/Hyprland/blob/v0.56.0/src/debug/HyprCtl.cpp).
No retry or claim of rollback is added.

Transport tests use temporary fake sockets, covering EOF, chunking, parallel
requests, missing env/socket, deadlines/limits, mixed batch errors and both
dispatcher dialects. No actual window dispatches are used in the tests.
