import SwiftUI
import OSLog
import HudsonSpeechEngine

@main
enum SpeechEntry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose-resources") {
            let root = Bundle.main.resourceURL!.appendingPathComponent("Vox_HudsonSpeechEngine.bundle")
            guard SpeechEngineResources.url(forResource: "mlx_audio_provider", withExtension: "py") != nil else {
                fputs("Bundled speech engine resources are missing\n", stderr)
                exit(1)
            }
            let models = ModelCatalogStore().asrModels(readyOnly: false)
            print("Speech resource catalog loaded: \(models.count) models; bundle=\(root.path)")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--diagnose-host"),
           CommandLine.arguments.indices.contains(index + 1) {
            let capability = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            SpeechRpc.register(on: .shared)
            SpeechRuntime.start(presentHUD: false, refreshVoices: false)
            let host = SpeechServer(port: 0, capabilityURL: capability)
            host.start()
            guard host.listeningPort > 0 else { exit(1) }
            print("{\"port\":\(host.listeningPort)}")
            fflush(stdout)
            signal(SIGTERM, SIG_IGN)
            let shutdown = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            shutdown.setEventHandler { host.stop(); exit(0) }
            shutdown.resume()
            withExtendedLifetime(shutdown) { RunLoop.main.run() }
            return
        }
        SpeechApp.main()
    }
}
struct SpeechApp: App {
    @NSApplicationDelegateAdaptor(SpeechAppDelegate.self) private var delegate
    @ObservedObject private var visibility = CompanionMenuBarVisibility.shared
    var body: some Scene {
        MenuBarExtra("Speech", systemImage: "waveform", isInserted: Binding(get: { visibility.isVisible }, set: { _ in })) {
            Button("Show Playback") { SpeechPlaybackHUD.shared.showFromMenu() }
            SettingsLink()
            Divider()
            Button("Quit Speech") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
        Settings { SpeechSettingsView().padding(20).frame(width: 540, height: 620).preferredColorScheme(.dark) }
    }
}
final class SpeechAppDelegate: NSObject, NSApplicationDelegate {
    private var controls: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        SpeechVoicePreferences.migrateLegacyDefaults()
        SpeechRpc.register(on: .shared)
        SpeechRuntime.start()
        SpeechServer.shared.start()
        if !CompanionMenuBarVisibility.shared.isVisible { showControls() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls(); return true
    }
    private func showControls() {
        if controls == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SpeechSettingsView().frame(width: 540, height: 620)))
            window.title = "Speech"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            controls = window
        }
        NSApp.activate(ignoringOtherApps: true)
        controls?.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification: Notification) { SpeechServer.shared.stop() }
}
enum SpeechEndpoints { static let rpcPort: UInt16 = 9397 }
final class DiagnosticLog {
    static let shared = DiagnosticLog()
    private let logger = Logger(subsystem: "dev.lattices.Speech", category: "runtime")
    func info(_ message: String) { logger.info("\(message, privacy: .private)") }
    func warn(_ message: String) { logger.warning("\(message, privacy: .private)") }
    func error(_ message: String) { logger.error("\(message, privacy: .private)") }
}
