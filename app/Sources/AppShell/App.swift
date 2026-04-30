import SwiftUI

@main
struct LatticesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsContentView(
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared
            )
            .frame(width: 900, height: 640)
        }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Update Lattices…") {
                        AppUpdater.shared.promptForUpdate()
                    }
                    .disabled(!AppUpdater.shared.canUpdate)

                    Divider()
                }
            }
    }
}
