export type HomeContext = {
  dir: string;
  sessionName: string;
  configLabel: string;
  paneNames: string;
  sessionsStatus: string;
  appStatus: string;
  tmuxReady: boolean;
};

export function printHome(ctx: HomeContext): void {
  console.log(`lattices — let's get you situated

Current directory:
  ${ctx.dir}

Workspace:
  session   ${ctx.sessionName}
  config    ${ctx.configLabel}
  panes     ${ctx.paneNames}
  sessions  ${ctx.sessionsStatus}
  app       ${ctx.appStatus}

Common commands:
  lattices start        Start or reattach this directory's workspace
  lattices init         Create a .lattices.json for this project
  lattices app          Launch the menu bar app
  lattices ls           List active sessions
  lattices help         Show the full command reference
`);

  if (!ctx.tmuxReady) {
    console.log("tmux is not installed. Run: brew install tmux");
  }
}

export function printUsage(): void {
  console.log(`lattices — workspace launcher for sessions, windows, layers, and the menu bar app

Usage:
  lattices                    Show workspace status and common commands
  lattices start              Start or reattach the current directory's workspace
  lattices init               Generate .lattices.json config for this project
  lattices ls                 List active sessions
  lattices status             Show managed vs unmanaged session inventory
  lattices kill [name]        Kill a session (defaults to current project)
  lattices sync               Reconcile session to match declared config
  lattices restart [pane]     Restart a pane's process (by name or index)
  lattices group [id]         List tab groups or launch/attach a group
  lattices groups             List all tab groups with status
  lattices tab <group> [tab]  Switch tab within a group (by label or index)
  lattices search <query>     Search windows by title, app, session, OCR
  lattices search <q> --deep  Deep search: index + live terminal inspection
  lattices search <q> --wid   Print matching window IDs only (pipeable)
  lattices search <q> --json  JSON output
  lattices place <query> [pos]  Deep search + focus + tile (default: bottom-right)
  lattices focus <session>    Raise a session's window
  lattices windows [--json]   List all desktop windows (daemon required)
  lattices sessions [--json]  List active sessions via daemon
  lattices terminals [--json] [--refresh]
                         List synthesized terminal instances
  lattices capture window [wid]  Save a screenshot run artifact
  lattices capture record window [wid]  Record a window/visible region as a .mov artifact
  lattices capture record-command --app Scout -- <cmd>
                         Record a target while running an action command
  lattices capture stop <run-id> Stop a running capture recording
  lattices runs [id] [--json] List recent runs or inspect one run
  lattices computer prepare      Resolve/stage a safe terminal action
  lattices computer focus-window Focus and verify a target window
  lattices computer launch-app  Launch/focus a normal macOS app
  lattices computer type-window Type into a normal app window
  lattices computer click       Stage or post a window-relative click
  lattices cua click            CLI alias for the CUA SDK click action
  lattices computer scout       Scout warm-up run for memo/demo recording
  lattices computer cursor       Show a recorded cursor appearance
  lattices computer type-text    Type text into a safe terminal target
  lattices computer demo-terminal  Record/focus/type a safe terminal demo
  lattices tile <position>    Tile the frontmost window (left, right, top, etc.)
  lattices tile family [app] [region]  Smart-grid the frontmost app family, or a named app
  lattices distribute [app] [region]   Smart-grid visible windows or just one app (daemon required)
  lattices layer [name|index]  List layers or switch by name/index (daemon required)
  lattices layer create <name> [wid:N ...] [--json '<specs>']  Create a session layer
  lattices layer snap [name]   Snapshot visible windows into a session layer
  lattices layer session [n]   List or switch session layers (runtime, no restart)
  lattices layer delete <name> Delete a session layer
  lattices layer clear         Clear all session layers
  lattices voice status       Voice provider status
  lattices voice simulate <t> Parse and execute a voice command
  lattices voice intents      List all available intents
  lattices actor app <app> [message]  Show a clickable app-icon actor
  lattices actor switcher [apps...]   Show a clickable app switcher row
  lattices actor hud <id> <url>       Attach a hover web HUD to an actor
  lattices actor toggle       Hide/show the sticky actor layer
  lattices hud register [manifest]    Register a .lattices/hud/manifest.json
  lattices hud publish [id|manifest]  Publish a registered/static HUD actor
  lattices assistant plan <t> Preview the TS assistant planner
  lattices call <method> [p]  Raw daemon API call (params as JSON)
  lattices scan               Show text from all visible windows
  lattices scan --full        Full text dump
  lattices scan search <q>    Full-text search across scanned windows
  lattices scan recent [n]    Show recent scans chronologically
  lattices scan deep          Trigger a deep Vision OCR scan
  lattices scan history <wid> Scan timeline for a specific window
  lattices dev                Run dev server (auto-detected)
  lattices dev build          Build the project (swift/node/rust/go/make)
  lattices dev restart        Build + restart (swift app) or just build
  lattices dev placement-smoke [a] [b]  Move two named sessions through verified placements
  lattices dev type           Print detected project type
  lattices mouse              Find mouse — sonar pulse at cursor position
  lattices mouse summon       Summon mouse to screen center
  lattices daemon status      Show daemon status
  lattices logs [limit]       Show activity log entries (aliases: log, activity, diag)
  lattices app                Launch the menu bar companion app
  lattices app update         Download the latest menu bar app and relaunch
  lattices app build          Rebuild the menu bar app
  lattices app restart        Rebuild and relaunch the menu bar app
  lattices app quit           Stop the menu bar app
  lattices help               Show this help

Config (.lattices.json):
  Place in your project root to customize the layout:

  {
    "ensure": true,
    "panes": [
      { "name": "shell", "size": 60 },
      { "name": "server", "cmd": "pnpm dev" },
      { "name": "tests",  "cmd": "pnpm test --watch" }
    ]
  }

  size      Width % for the first pane (default: 60)
  cmd       Command to run in the pane
  name      Label (for your reference)
  ensure    Auto-restart exited commands on reattach
  prefill   Type commands into idle panes on reattach (you hit Enter)

Recovery:
  lattices sync       Recreates missing panes, restores commands, fixes layout.
                    Use when a pane was killed and you want to get back to the
                    declared state without killing the whole session.

  lattices restart    Kills the process in a pane and re-runs its declared command.
                    Accepts a pane name or 0-based index (default: 0 / first pane).
                    Examples:  lattices restart         (restarts the first pane)
                               lattices restart server  (restarts "server" by name)
                               lattices restart 1       (restarts pane at index 1)

Layouts:
  1 pane   →  single full-width (default when no dev server detected)
  2 panes  →  side-by-side split
  3+ panes →  main-vertical (first pane left, rest stacked right)

  ┌────────────────────┐    ┌──────────┬─────────┐    ┌──────────┬─────────┐
  │      shell          │    │  shell    │ server  │    │  shell    │ server  │
  │                     │    │  (60%)   │ (40%)   │    │  (60%)   ├─────────┤
  └────────────────────┘    └──────────┴─────────┘    │          │ tests   │
                                                       └──────────┴─────────┘
`);
}