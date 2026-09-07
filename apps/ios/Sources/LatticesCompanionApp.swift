import SwiftUI

@main
struct LatticesCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--fleet-design") {
                // The design source's own data, for comparison against the artifact.
                FleetDeckPreviewHost(machineCount: 4, useDesignFixture: true)
            } else if ProcessInfo.processInfo.arguments.contains("--fleet-preview") {
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
