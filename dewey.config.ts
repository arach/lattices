/** @type {import('@arach/dewey').DeweyConfig} */
export default {
  project: {
    name: 'lattice',
    tagline: 'Developer workspace launcher — Claude Code + dev server in tmux, with a native macOS menu bar app',
    type: 'cli-tool',
    version: '0.1.0',
  },

  agent: {
    criticalContext: [
      'lattice has TWO interfaces: a Node.js CLI (`bin/lattice.js`) and a native Swift menu bar app (`app/Sources/`)',
      'Session names are `<basename>-<sha256-6chars>` — both CLI and app must produce identical hashes',
      'The app finds terminal windows via a `[lattice:session-name]` tag embedded in the tmux window title',
      'Window navigation falls through CG → AX → AppleScript depending on macOS permissions',
      'Space switching uses private SkyLight framework APIs loaded via dlopen at runtime',
    ],

    entryPoints: {
      'cli': 'bin/lattice.js',
      'app-helper': 'bin/lattice-app.js',
      'menu-bar-app': 'app/Sources/',
      'website': 'www/',
      'docs': 'docs/',
    },

    rules: [
      { pattern: 'cli', instruction: 'Check bin/lattice.js for CLI commands and session logic' },
      { pattern: 'app', instruction: 'Check app/Sources/ for Swift menu bar app code' },
      { pattern: 'config', instruction: 'Check docs/config.md for .lattice.json format and CLI reference' },
      { pattern: 'tiling', instruction: 'Check app/Sources/WindowTiler.swift and bin/lattice.js tilePresets' },
      { pattern: 'palette', instruction: 'Check app/Sources/PaletteCommand.swift for command palette actions' },
      { pattern: 'terminal', instruction: 'Check app/Sources/Terminal.swift for supported terminals and launch logic' },
    ],

    sections: ['concepts', 'config', 'app'],
  },

  docs: {
    path: './docs',
    output: './',
    required: ['concepts', 'config'],
  },

  install: {
    objective: 'Install lattice CLI and optionally the menu bar companion app.',

    doneWhen: {
      command: 'lattice help',
      expectedOutput: 'Usage information for lattice',
    },

    prerequisites: [
      'macOS 13.0+',
      'tmux (brew install tmux)',
      'Node.js >= 18',
    ],

    steps: [
      { description: 'Install tmux if not present', command: 'brew install tmux' },
      { description: 'Clone the repository', command: 'git clone https://github.com/arach/lattice && cd lattice' },
      { description: 'Link the CLI globally', command: 'npm link' },
      { description: 'Launch the menu bar app', command: 'lattice app' },
      { description: 'Create a config in your project', command: 'cd ~/your-project && lattice init' },
      { description: 'Start your workspace', command: 'lattice' },
    ],
  },
}
