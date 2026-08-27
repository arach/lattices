/** @type {import('@arach/dewey').DeweyConfig} */
export default {
  project: {
    name: 'action',
    tagline: 'Native-first macOS demo automation with an AppKit UI and a local agent runtime',
    type: 'monorepo',
    version: '0.0.0',
  },

  agent: {
    criticalContext: [
      'Use bun as the JavaScript package manager for this repo.',
      'Action lives under products/action in the Lattices monorepo; run these commands from the product directory.',
      'The native product lives in native/engine and builds a signed Action.app bundle.',
      'Action.app owns AppKit lifecycle, menus, WebKit, permissions UX, and the recording probe path.',
      'The local Action agent exposes WebSocket methods and should not own fragile AppKit lifecycle responsibilities directly.',
      'ScreenCaptureKit recording is currently stabilized by launching a fresh Action.app instance in recording-probe mode.',
      'Recording commands should be treated as asynchronous: the initial CLI reply acknowledges startup, while completion is represented by a finished marker file.',
      'The repo still contains older design docs in docs/*.md that describe architecture and product direction beyond the Dewey quickstart set.',
    ],

    entryPoints: {
      root: 'README.md',
      dewey: 'dewey.config.ts',
      native: 'native/engine/',
      appHost: 'native/engine/Sources/ActionHostMain.swift',
      agentRuntime: 'native/engine/CoreSources/ActionAgentRuntime.swift',
      recordingProbe: 'native/engine/Sources/RecordingProbeAppRunner.swift',
      launcher: 'native/engine/Sources/ActionLauncherViewModel.swift',
      docs: 'docs/',
    },

    rules: [
      { pattern: 'webkit', instruction: 'Read docs/native-runtime.md and native/engine/Sources/ActionHostMain.swift for the AppKit-owned UI lifecycle.' },
      { pattern: 'record', instruction: 'Read docs/recording.md and native/engine/CoreSources/ActionRecordingProbeLauncher.swift before changing recording behavior.' },
      { pattern: 'agent', instruction: 'Read docs/native-runtime.md and native/engine/CoreSources/ActionAgentRuntime.swift for the current app/agent split.' },
      { pattern: 'permission', instruction: 'Check native/engine/Sources/ActionLauncherViewModel.swift and the native wrapper scripts in native/engine/scripts/.' },
      { pattern: 'build', instruction: 'Use bun run native:doctor or native/engine/scripts/build-app.sh to produce a signed app bundle.' },
      { pattern: 'theme', instruction: 'Read docs/theming.agent.md before changing colour, type or metrics. Views paint through StageHUDTheme, which resolves whichever ActionTheme is installed; themes are patches authored as JSON.' },
    ],

    sections: ['overview', 'getting-started', 'native-runtime', 'recording'],
  },

  docs: {
    path: './docs',
    output: './',
    required: ['overview', 'getting-started', 'native-runtime', 'recording'],
  },

  install: {
    objective: 'Build the signed Action.app bundle and verify the native host is in a healthy state.',
    doneWhen: {
      command: 'bun run native:doctor',
    },
    prerequisites: [
      'macOS on Apple Silicon',
      'Bun 1.3+',
      'Xcode command line tools and native build prerequisites for Swift/AppKit development',
      'Accessibility and Screen Recording permissions may be required for capture and automation smoke tests',
    ],
    steps: [
      { description: 'Clone the repository', command: 'git clone https://github.com/arach/lattices.git && cd lattices/products/action' },
      { description: 'Install JavaScript dependencies', command: 'bun install' },
      { description: 'Build and sign the native app', command: 'bun run native:app:build' },
      { description: 'Verify the native host and current permission state', command: 'bun run native:doctor' },
      { description: 'Run a screenshot smoke test', command: 'bun run native:test:screenshot' },
    ],
  },
}
