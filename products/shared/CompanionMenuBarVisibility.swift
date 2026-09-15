import AppKit
import SwiftUI

/// Compiled into each companion. Preferences and observers belong to that app.
@MainActor
final class CompanionMenuBarVisibility: ObservableObject {
    static let shared = CompanionMenuBarVisibility()
    static let preferenceKey = "companion.alwaysShowMenuBarIcon"
    static let latticesBundleIDs: Set<String> = ["com.arach.lattices", "dev.lattices.app", "dev.lattices.app.dev"]
    @Published private(set) var isVisible = true
    @Published var alwaysShow: Bool { didSet {
        guard oldValue != alwaysShow else { return }
        if let persist { persist(alwaysShow) } else { defaults.set(alwaysShow, forKey: Self.preferenceKey) }
        refresh()
    } }
    private var persist: ((Bool) -> Void)?
    func usePreference(alwaysShow: Bool, persist: @escaping (Bool) -> Void) {
        self.persist = persist
        self.alwaysShow = alwaysShow
        refresh()
    }
    var onChange: ((Bool) -> Void)?
    private let defaults: UserDefaults
    private let observation = CompanionWorkspaceObservation()

    static func visible(alwaysShow: Bool, runningBundleIDs: Set<String>) -> Bool {
        alwaysShow || latticesBundleIDs.isDisjoint(with: runningBundleIDs)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alwaysShow = defaults.bool(forKey: Self.preferenceKey)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observation.tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let terminatedPID = name == NSWorkspace.didTerminateApplicationNotification ? app?.processIdentifier : nil
                let launchedID = name == NSWorkspace.didLaunchApplicationNotification ? app?.bundleIdentifier : nil
                Task { @MainActor in self?.refresh(excluding: terminatedPID, including: launchedID) }
            })
        }
        refresh()
    }
    private func refresh(excluding pid: pid_t? = nil, including bundleID: String? = nil) {
        var ids = Set(NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != pid }.compactMap(\.bundleIdentifier))
        if let bundleID { ids.insert(bundleID) }
        isVisible = Self.visible(alwaysShow: alwaysShow, runningBundleIDs: ids)
        onChange?(isVisible)
    }
}

// Tokens are installed only during main-actor initialization. NotificationCenter
// removal is thread safe, so teardown need not cross into the main actor.
private final class CompanionWorkspaceObservation: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    deinit {
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}

struct CompanionMenuBarPreference: View {
    @ObservedObject private var visibility = CompanionMenuBarVisibility.shared
    var body: some View {
        Toggle("Always show menu bar icon", isOn: $visibility.alwaysShow)
            .help("When off, the icon appears automatically whenever Lattices is not running. You can always reopen this app from Finder or Lattices Apps.")
    }
}
