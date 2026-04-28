import SwiftUI

@main
struct LatticesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
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
