import AppKit
import Foundation

/// Opens an app, or a URL in an app, without activating it: nothing comes to the
/// front and the operator's focus stays where it is.
///
/// A running app with no windows gets the reopen a Dock click sends, which is how
/// most apps open a fresh window. Where that window appears is the app's call; an
/// agent layer adopts it from there.
enum ActionBackgroundOpen {
    @MainActor
    static func open(bundleId: String, url: URL?) async throws -> NSRunningApplication {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw ActionHostError.accessibilityActionFailed("No app is installed with bundle id \(bundleId)")
        }
        return try await open(appURL: appURL, url: url)
    }

    @MainActor
    static func open(_ app: NSRunningApplication, url: URL?) async throws -> NSRunningApplication {
        guard let appURL = app.bundleURL else {
            throw ActionHostError.accessibilityActionFailed("\(targetLabel(for: app)) has no bundle to open")
        }
        return try await open(appURL: appURL, url: url)
    }

    @MainActor
    private static func open(appURL: URL, url: URL?) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        if let url {
            return try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
        return try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// `--url`: a full URL, or a bare host such as `news.ycombinator.com` read as https.
    static func url(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.contains("://") || value.hasPrefix("about:") || value.hasPrefix("mailto:") {
            return URL(string: value)
        }
        if value.hasPrefix("/") || value.hasPrefix("~") {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        }
        return URL(string: "https://\(value)")
    }
}
