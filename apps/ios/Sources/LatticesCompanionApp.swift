import SwiftUI

@main
struct LatticesCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--fleet-preview") {
                FleetDeckPreviewHost(machineCount: 4)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
