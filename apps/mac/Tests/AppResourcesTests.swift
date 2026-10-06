import XCTest
@testable import Lattices

final class AppResourcesTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppResourcesTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// The DMG layout: SwiftPM's resource bundle sits in Contents/Resources,
    /// where the generated `Bundle.module` accessor never looks.
    func testFindsEditorInsidePackagedResourceBundle() throws {
        let app = scratch.appendingPathComponent("Lattices.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let editor = resources.appendingPathComponent("Lattices_Lattices.bundle/Editor", isDirectory: true)
        try FileManager.default.createDirectory(at: editor, withIntermediateDirectories: true)

        let roots = AppResources.roots(
            named: "Editor",
            applicationResourceURL: resources,
            applicationBundleURL: app,
            loadedBundles: []
        )

        XCTAssertTrue(roots.contains { $0.standardizedFileURL.path == editor.standardizedFileURL.path })
    }

    /// `swift run`: the resource bundle sits beside the executable.
    func testFindsEditorBesideTheExecutable() throws {
        let release = scratch.appendingPathComponent("release", isDirectory: true)
        let editor = release.appendingPathComponent("Lattices_Lattices.bundle/Editor", isDirectory: true)
        try FileManager.default.createDirectory(at: editor, withIntermediateDirectories: true)

        let roots = AppResources.roots(
            named: "Editor",
            applicationResourceURL: nil,
            applicationBundleURL: release,
            loadedBundles: []
        )

        XCTAssertTrue(roots.contains { $0.standardizedFileURL.path == editor.standardizedFileURL.path })
    }

    /// `Bundle.module` traps on any Mac but the one that built the app, and
    /// the build machine is exactly where a smoke test can't see it.
    func testSourcesNeverUseBundleModule() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))

        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = text.split(separator: "\n").filter {
                !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
            }
            if code.contains(where: { $0.contains("Bundle.module") }) {
                offenders.append(url.lastPathComponent)
            }
        }

        XCTAssertEqual(offenders, [], "Use AppResources instead of Bundle.module")
    }
}
