import AppKit
import Foundation

protocol CompanionLaunchServicesLocating {
    func urlForApplication(bundleIdentifier: String) -> URL?
}

protocol CompanionBundleIdentityReading {
    func bundleIdentifier(at url: URL) -> String?
}

protocol CompanionAppFileSystem {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    func contentsOfDirectory(_ url: URL) -> [URL]
}

struct WorkspaceCompanionLaunchServices: CompanionLaunchServicesLocating {
    func urlForApplication(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

/// Reads `CFBundleIdentifier` from an on-disk bundle. A file named like an app
/// is not an install.
struct PlistCompanionBundleIdentityReader: CompanionBundleIdentityReading {
    func bundleIdentifier(at url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue, resolved.pathExtension == "app"
        else { return nil }

        let plistURL = resolved.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        guard FileManager.default.isReadableFile(atPath: plistURL.path),
              let dict = NSDictionary(contentsOf: plistURL),
              dict["CFBundlePackageType"] as? String == "APPL",
              let executable = dict["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != "..",
              FileManager.default.isExecutableFile(atPath: resolved.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path),
              let identifier = dict["CFBundleIdentifier"] as? String
        else { return nil }

        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct FoundationCompanionAppFileSystem: CompanionAppFileSystem {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    func contentsOfDirectory(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

/// Launch Services plus standard Applications folders. Identity is re-read from
/// disk; process presence, filename, and cached paths are not enough.
struct CompanionAppDiscovery {
    var launchServices: CompanionLaunchServicesLocating
    var identityReader: CompanionBundleIdentityReading
    var fileSystem: CompanionAppFileSystem
    var applicationsDirectories: [URL]

    static let system = CompanionAppDiscovery(
        launchServices: WorkspaceCompanionLaunchServices(),
        identityReader: PlistCompanionBundleIdentityReader(),
        fileSystem: FoundationCompanionAppFileSystem(),
        applicationsDirectories: [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
    )

    func validatedURL(bundleIdentifier: String) -> URL? {
        if let url = launchServices.urlForApplication(bundleIdentifier: bundleIdentifier),
           identityReader.bundleIdentifier(at: url) == bundleIdentifier {
            return url.resolvingSymlinksInPath()
        }
        for directory in applicationsDirectories {
            for item in fileSystem.contentsOfDirectory(directory) where item.pathExtension == "app" {
                if identityReader.bundleIdentifier(at: item) == bundleIdentifier {
                    return item.resolvingSymlinksInPath()
                }
            }
        }
        return nil
    }

    func installState(for product: CompanionProduct) -> CompanionInstallState {
        guard let bundleIdentifier = product.bundleIdentifier,
              let url = validatedURL(bundleIdentifier: bundleIdentifier)
        else { return .missing }
        return .installed(url: url)
    }

    func installedURLs(for product: CompanionProduct) -> [URL] {
        switch installState(for: product) {
        case .installed(let url):
            return [url]
        case .missing:
            return []
        }
    }
}
