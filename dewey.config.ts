/** @type {import('@arach/dewey').DeweyConfig} */
export default {
  project: {
    name: 'lattices',
    tagline: 'macOS developer workspace manager — tmux sessions with a native menu bar app for tiling, navigation, and project management',
    type: 'cli-tool',
    version: '0.1.0',
  },

  agent: {
    criticalContext: [
      'lattices has TWO interfaces: a Node.js CLI (`bin/lattices.js`) and a native Swift menu bar app (`app/Sources/`)',
      'Session names are `<basename>-<sha256-6chars>` — both CLI and app must produce identical hashes',
      'The app finds terminal windows via a `[lattices:session-name]` tag embedded in the tmux window title',
      'Window navigation falls through CG → AX → AppleScript depending on macOS permissions',
      'Space switching uses private SkyLight framework APIs loaded via dlopen at runtime',
      'The daemon runs on ws://127.0.0.1:9399 with 20 RPC methods and 3 real-time events',
    ],

    entryPoints: {
      'cli': 'bin/lattices.js',
      'app-helper': 'bin/lattices-app.js',
      'menu-bar-app': 'app/Sources/',
      'docs': 'docs/',
      'docs-site': 'docs-site/',
      'marketing-site': 'site/',
    },

    rules: [
      { pattern: 'cli', instruction: 'Check bin/lattices.js for CLI commands and session logic' },
      { pattern: 'app', instruction: 'Check app/Sources/ for Swift menu bar app code' },
      { pattern: 'config', instruction: 'Check docs/config.md for .lattices.json format and CLI reference' },
      { pattern: 'tiling', instruction: 'Check app/Sources/WindowTiler.swift and bin/lattices.js tilePresets' },
      { pattern: 'palette', instruction: 'Check app/Sources/PaletteCommand.swift for command palette actions' },
      { pattern: 'terminal', instruction: 'Check app/Sources/Terminal.swift for supported terminals and launch logic' },
      { pattern: 'daemon', instruction: 'Check app/Sources/DaemonServer.swift and app/Sources/LatticesApi.swift for WebSocket API' },
      { pattern: 'api', instruction: 'Check docs/api.md for the full 20-method RPC reference' },
      { pattern: 'twin', instruction: 'Check docs/twins.md and bin/project-twin.ts for the Pi-backed project twin runtime' },
    ],

    sections: ['overview', 'quickstart', 'concepts', 'twins', 'config', 'app', 'api', 'layers'],
  },

  docs: {
    path: './docs',
    output: './',
    required: ['overview', 'quickstart', 'concepts', 'config'],
  },

  install: {
    objective: 'Install the lattices CLI and optionally the native macOS menu bar companion app.',

    doneWhen: {
      command: 'lattices help',
      expectedOutput: 'Usage information for lattices CLI',
    },

    prerequisites: [
      'macOS 13.0+',
      'tmux (brew install tmux)',
      'Node.js >= 18',
      'Swift 5.9+ (only if building the menu bar app from source)',
    ],

    steps: [
      { description: 'Install tmux if not present', command: 'brew install tmux' },
      { description: 'Clone the repository', command: 'git clone https://github.com/arach/lattices && cd lattices' },
      { description: 'Link the CLI globally', command: 'bun link' },
      { description: 'Build and launch the menu bar app', command: 'lattices app' },
      { description: 'Create a config in your project', command: 'cd ~/your-project && lattices init' },
      { description: 'Start your first workspace', command: 'lattices' },
    ],
  },
}
