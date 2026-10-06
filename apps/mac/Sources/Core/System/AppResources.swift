import Foundation

/// Finds bundled resource folders (Editor, DeckBuilder, ...) without touching
/// `Bundle.module`. Its generated accessor only checks the app root and the
/// build machine's `.build` path, so in a packaged app, which keeps SwiftPM's
/// resource bundles in Contents/Resources, it traps on every other Mac.
enum AppResources {
    /// Candidate locations for `name`, most specific first: the app's own
    /// Resources, any loaded bundle, then SwiftPM resource bundles sitting in
    /// Resources or beside the executable (`swift run`).
    static func roots(
        named name: String,
        applicationResourceURL: URL? = Bundle.main.resourceURL,
        applicationBundleURL: URL? = Bundle.main.bundleURL,
        loadedBundles: [Bundle] = Bundle.allBundles + Bundle.allFrameworks,
        fileManager: FileManager = .default
    ) -> [URL] {
        var resourceURLs = [applicationResourceURL].compactMap { $0 }
        resourceURLs.append(contentsOf: loadedBundles.compactMap(\.resourceURL))

        for directory in [applicationResourceURL, applicationBundleURL].compactMap({ $0 }) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }
            resourceURLs.append(contentsOf: children.compactMap { child in
                guard child.pathExtension == "bundle" else { return nil }
                return Bundle(url: child)?.resourceURL
            })
        }

        var seen = Set<String>()
        return resourceURLs
            .map { $0.appendingPathComponent(name, isDirectory: true) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// The first candidate for `name` that exists on disk.
    static func directory(named name: String, fileManager: FileManager = .default) -> URL? {
        roots(named: name, fileManager: fileManager).first { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}
