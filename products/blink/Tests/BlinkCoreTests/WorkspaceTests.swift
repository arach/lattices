import Testing
import Foundation
@testable import BlinkCore

@Suite("Treatment composition")
struct TreatmentTests {
    @Test("A fresh treatment is empty — unbranded is the default")
    func emptyByDefault() {
        #expect(Treatment().isEmpty)
        var t = Treatment()
        t.accent = "#a6ef87"
        #expect(!t.isEmpty)
    }

    @Test("Merging overlays only the fields the other side sets")
    func mergingIsPartial() {
        var base = Treatment()
        base.accent = "#base"
        base.font = "Base Font"
        base.radius = 12

        var overlay = Treatment()
        overlay.accent = "#overlay"

        let merged = base.merging(overlay)
        #expect(merged.accent == "#overlay")   // overlay wins
        #expect(merged.font == "Base Font")    // untouched field inherits
        #expect(merged.radius == 12)
    }

    @Test("Merging an empty treatment changes nothing")
    func mergingEmptyIsIdentity() {
        var base = Treatment()
        base.background = "#070908"
        base.mark = "marks/acme.svg"
        #expect(base.merging(Treatment()) == base)
    }

    @Test("Decodes partial JSON and ignores foreign keys")
    func decodesPartial() throws {
        let json = ##"{"accent":"#a6ef87","radius":6,"somethingElse":"ignored"}"##
        let t = try JSONDecoder().decode(Treatment.self, from: Data(json.utf8))
        #expect(t.accent == "#a6ef87")
        #expect(t.radius == 6)
        #expect(t.background == nil)
    }

    @Test("Encoding omits unset fields, so a brand stays minimal on disk")
    func encodesSparse() throws {
        var t = Treatment()
        t.accent = "#a6ef87"
        let data = try JSONEncoder().encode(t)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.count == 1)
        #expect(object["accent"] as? String == "#a6ef87")
    }
}

@Suite("Workspace brand resolution")
struct WorkspaceBrandTests {
    @Test("An unbranded workspace resolves to an empty brand")
    func unbranded() {
        #expect(Workspace().resolvedBrand(styles: nil).isEmpty)
    }

    @Test("A named style is the base; the inline brand overlays it")
    func styleThenBrand() {
        var house = Treatment()
        house.font = "House Font"
        house.accent = "#house"

        var brand = Treatment()
        brand.accent = "#mine"

        let ws = Workspace(title: "Mine", style: "house", brand: brand)
        let resolved = ws.resolvedBrand(styles: ["house": house])
        #expect(resolved.font == "House Font")  // inherited from the shared base
        #expect(resolved.accent == "#mine")     // the workspace's own brand wins
    }

    @Test("An unknown style name contributes nothing rather than failing")
    func unknownStyleIsIgnored() {
        var brand = Treatment()
        brand.accent = "#mine"
        let ws = Workspace(style: "does-not-exist", brand: brand)
        let resolved = ws.resolvedBrand(styles: ["other": Treatment()])
        #expect(resolved.accent == "#mine")
    }
}

@Suite("Presentation resolution order")
struct PresentationResolverTests {
    private func treatment(_ build: (inout Treatment) -> Void) -> Treatment {
        var t = Treatment()
        build(&t)
        return t
    }

    private var styles: [String: Treatment] {
        [
            "house": treatment { $0.accent = "#house"; $0.font = "House"; $0.radius = 20 },
            "focus": treatment { $0.accent = "#focus" },
        ]
    }

    private var workspaces: [String: Workspace] {
        [
            "acme": Workspace(
                title: "Acme",
                style: "house",
                brand: treatment { $0.accent = "#acme"; $0.background = "#0b0d0c" }
            ),
            "bare": Workspace(title: "Bare"),
        ]
    }

    @Test("A note with no workspace and no style is unaffected — today's behavior")
    func plainNoteIsUntouched() {
        let effective = PresentationResolver.effective(
            for: NotePresentation(), styles: styles, workspaces: workspaces
        )
        #expect(effective.isEmpty)
        #expect(PresentationResolver.chain(
            for: NotePresentation(), styles: styles, workspaces: workspaces
        ).isEmpty)
    }

    @Test("A workspace note inherits the brand without carrying any of it")
    func workspaceBrandApplies() {
        var p = NotePresentation()
        p.workspace = "acme"
        let effective = PresentationResolver.effective(for: p, styles: styles, workspaces: workspaces)
        #expect(effective.accent == "#acme")        // workspace brand over its style base
        #expect(effective.background == "#0b0d0c")
        #expect(effective.font == "House")          // inherited through the base style
        #expect(effective.radius == 20)
    }

    /// The escape hatch that keeps a brand from being a cage: a note in a
    /// branded workspace can still name its own style, and that wins.
    @Test("A per-note style overrides the workspace brand")
    func styleBeatsWorkspace() {
        var p = NotePresentation()
        p.workspace = "acme"
        p.style = "focus"
        let effective = PresentationResolver.effective(for: p, styles: styles, workspaces: workspaces)
        #expect(effective.accent == "#focus")       // the note's style wins
        #expect(effective.background == "#0b0d0c")  // brand still supplies the rest
    }

    @Test("Loose per-note keys beat both the style and the workspace brand")
    func looseKeysWinOutright() {
        var p = NotePresentation()
        p.workspace = "acme"
        p.style = "focus"
        p.accent = "#mine"
        p.radius = 3
        let effective = PresentationResolver.effective(for: p, styles: styles, workspaces: workspaces)
        #expect(effective.accent == "#mine")
        #expect(effective.radius == 3)
    }

    @Test("Precedence is workspace → style → loose, in that order")
    func chainOrder() {
        var p = NotePresentation()
        p.workspace = "acme"
        p.style = "focus"
        p.accent = "#mine"
        let chain = PresentationResolver.chain(for: p, styles: styles, workspaces: workspaces)
        #expect(chain.count == 3)
        #expect(chain[0].accent == "#acme")   // workspace brand, least specific
        #expect(chain[1].accent == "#focus")  // named style
        #expect(chain[2].accent == "#mine")   // loose per-note key, most specific
    }

    @Test("An unknown workspace name renders unbranded rather than failing")
    func unknownWorkspaceIsIgnored() {
        var p = NotePresentation()
        p.workspace = "was-forgotten"
        let effective = PresentationResolver.effective(for: p, styles: styles, workspaces: workspaces)
        #expect(effective.isEmpty)
    }

    @Test("A workspace with no brand contributes nothing to the chain")
    func unbrandedWorkspaceIsNoOp() {
        var p = NotePresentation()
        p.workspace = "bare"
        #expect(PresentationResolver.chain(for: p, styles: styles, workspaces: workspaces).isEmpty)
    }

    @Test("Notes still resolve when no workspaces are configured at all")
    func backwardCompatibleWithoutWorkspaces() {
        var p = NotePresentation()
        p.workspace = "acme"
        p.style = "focus"
        let effective = PresentationResolver.effective(for: p, styles: styles, workspaces: nil)
        #expect(effective.accent == "#focus")
    }

    @Test("Slot is placement, not presentation — it never enters the chain")
    func slotIsNotPresentation() {
        var p = NotePresentation()
        p.slot = 6
        #expect(PresentationResolver.chain(for: p, styles: nil, workspaces: nil).isEmpty)
    }
}

@Suite("Attachment containment")
struct AttachmentPathTests {
    private func sandbox() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func env(_ home: URL) -> [String: String] { ["BLINK_HOME": home.path] }

    @Test("Resolves a real file inside the attachments directory")
    func resolvesInside() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let marks = BlinkPaths.marks(environment: env(home))
        try FileManager.default.createDirectory(at: marks, withIntermediateDirectories: true)
        try Data("<svg/>".utf8).write(to: marks.appendingPathComponent("acme.svg"))

        let url = BlinkPaths.attachment(named: "marks/acme.svg", environment: env(home))
        #expect(url != nil)
        #expect(url?.lastPathComponent == "acme.svg")
    }

    @Test("Accepts the blink:// attachment form the editor uses")
    func acceptsBlinkScheme() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let marks = BlinkPaths.marks(environment: env(home))
        try FileManager.default.createDirectory(at: marks, withIntermediateDirectories: true)
        try Data("<svg/>".utf8).write(to: marks.appendingPathComponent("acme.svg"))

        #expect(BlinkPaths.attachment(named: "blink://attachments/marks/acme.svg", environment: env(home)) != nil)
    }

    @Test("Rejects absolute paths, traversal, tildes, and missing files")
    func rejectsOutOfBounds() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: BlinkPaths.attachments(environment: env(home)), withIntermediateDirectories: true
        )
        // A real file that lives outside the attachments root.
        let outside = home.appendingPathComponent("secret.svg")
        try Data("<svg/>".utf8).write(to: outside)

        let e = env(home)
        #expect(BlinkPaths.attachment(named: "/etc/passwd", environment: e) == nil)
        #expect(BlinkPaths.attachment(named: outside.path, environment: e) == nil)
        #expect(BlinkPaths.attachment(named: "../secret.svg", environment: e) == nil)
        #expect(BlinkPaths.attachment(named: "~/secret.svg", environment: e) == nil)
        #expect(BlinkPaths.attachment(named: "marks/nope.svg", environment: e) == nil)
        #expect(BlinkPaths.attachment(named: "", environment: e) == nil)
        #expect(BlinkPaths.attachment(named: nil, environment: e) == nil)
    }

    @Test("Rejects a symlink that escapes the attachments directory")
    func rejectsEscapingSymlink() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let attachments = BlinkPaths.attachments(environment: env(home))
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let outside = home.appendingPathComponent("secret.svg")
        try Data("<svg/>".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: attachments.appendingPathComponent("escape.svg"), withDestinationURL: outside
        )

        #expect(BlinkPaths.attachment(named: "escape.svg", environment: env(home)) == nil)
    }

    @Test("A directory is not an attachment")
    func rejectsDirectory() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let marks = BlinkPaths.marks(environment: env(home))
        try FileManager.default.createDirectory(at: marks, withIntermediateDirectories: true)
        #expect(BlinkPaths.attachment(named: "marks", environment: env(home)) == nil)
    }
}

@Suite("WorkspaceStore")
struct WorkspaceStoreTests {
    private func sandbox() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkWorkspaceStore-\(UUID().uuidString)", isDirectory: true)
    }

    private func write(_ json: String, to home: URL) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: home.appendingPathComponent("config.json"))
    }

    private func readConfig(_ home: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: home.appendingPathComponent("config.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Names

    @Test("Names normalize to slugs so one workspace has one identity")
    func normalizesNames() throws {
        #expect(try WorkspaceStore.normalize("Q3 Planning") == "q3-planning")
        #expect(try WorkspaceStore.normalize("  acme_docs  ") == "acme-docs")
    }

    @Test("Names with no usable characters are rejected, not silently collapsed")
    func rejectsUnusableNames() {
        #expect(throws: WorkspaceStoreError.self) { try WorkspaceStore.normalize("") }
        #expect(throws: WorkspaceStoreError.self) { try WorkspaceStore.normalize("   ") }
        #expect(throws: WorkspaceStoreError.self) { try WorkspaceStore.normalize("---") }
    }

    // MARK: Read/write

    @Test("Missing config means no workspaces, not an error")
    func absentConfigIsEmpty() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(try WorkspaceStore(home: home).all().isEmpty)
    }

    @Test("Save then read round-trips a branded workspace")
    func roundTrip() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WorkspaceStore(home: home)

        var brand = Treatment()
        brand.accent = "#a6ef87"
        brand.radius = 6
        brand.mark = "marks/acme.svg"
        try store.save(Workspace(title: "Acme Docs", brand: brand), named: "Acme Docs")

        let loaded = try #require(try store.workspace(named: "acme-docs"))
        #expect(loaded.title == "Acme Docs")
        #expect(loaded.brand?.accent == "#a6ef87")
        #expect(loaded.brand?.radius == 6)
        #expect(loaded.brand?.mark == "marks/acme.svg")
    }

    /// The load-bearing guarantee: config.json is a shared surface, so writing a
    /// workspace must not disturb any other key — including keys this build has
    /// never heard of.
    @Test("Writing a workspace preserves every other config key verbatim")
    func preservesForeignConfig() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            """
            {
              "appearance": "dark",
              "hotkeys": { "newNote": "hyper+n", "blink": "hyper+b" },
              "panel": { "sheet": "glass", "cornerRadius": 12, "tintRead": 0.18 },
              "styles": { "focus": { "accent": "#d08770" } },
              "somethingFromTheFuture": { "nested": [1, 2, 3], "flag": true }
            }
            """,
            to: home
        )

        try WorkspaceStore(home: home).save(Workspace(title: "Acme"), named: "acme")

        let config = try readConfig(home)
        #expect(config["appearance"] as? String == "dark")
        #expect((config["hotkeys"] as? [String: Any])?["newNote"] as? String == "hyper+n")
        #expect((config["panel"] as? [String: Any])?["cornerRadius"] as? Double == 12)
        #expect((config["panel"] as? [String: Any])?["tintRead"] as? Double == 0.18)
        #expect(((config["styles"] as? [String: Any])?["focus"] as? [String: Any])?["accent"] as? String == "#d08770")
        let future = try #require(config["somethingFromTheFuture"] as? [String: Any])
        #expect(future["flag"] as? Bool == true)
        #expect((future["nested"] as? [Int]) == [1, 2, 3])
        #expect(config["workspaces"] != nil)
    }

    @Test("An unreadable config is never overwritten")
    func refusesToClobberBadConfig() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let broken = "{ this is not json"
        try write(broken, to: home)

        #expect(throws: WorkspaceStoreError.self) {
            try WorkspaceStore(home: home).save(Workspace(), named: "acme")
        }
        let after = try String(contentsOf: home.appendingPathComponent("config.json"), encoding: .utf8)
        #expect(after == broken)
    }

    @Test("update edits one field without restating the brand")
    func partialUpdate() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WorkspaceStore(home: home)

        var brand = Treatment()
        brand.accent = "#old"
        brand.font = "Keep Me"
        try store.save(Workspace(title: "Acme", brand: brand), named: "acme")

        try store.update(named: "acme") { ws in
            ws.brand?.accent = "#new"
        }

        let loaded = try #require(try store.workspace(named: "acme"))
        #expect(loaded.brand?.accent == "#new")
        #expect(loaded.brand?.font == "Keep Me")
        #expect(loaded.title == "Acme")
    }

    @Test("update refuses to invent a workspace when told not to")
    func updateRequiresExisting() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(throws: WorkspaceStoreError.self) {
            try WorkspaceStore(home: home).update(named: "ghost", createIfMissing: false) { _ in }
        }
    }

    @Test("Removing the last workspace drops the key instead of leaving an empty object")
    func removeCleansUp() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WorkspaceStore(home: home)
        try store.save(Workspace(), named: "acme")
        #expect(try store.remove(named: "acme"))
        #expect(try !store.remove(named: "acme"))
        #expect(try readConfig(home)["workspaces"] == nil)
    }

    @Test("Styles registry is readable for brand composition")
    func readsStyles() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(##"{"styles":{"focus":{"accent":"#d08770","radius":7}}}"##, to: home)
        let styles = try WorkspaceStore(home: home).styles()
        #expect(styles["focus"]?.accent == "#d08770")
        #expect(styles["focus"]?.radius == 7)
    }

    // MARK: Marks

    @Test("Installing a mark copies it into attachments and returns a relative path")
    func installsMark() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WorkspaceStore(home: home)

        let source = home.appendingPathComponent("logo.svg")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("<svg/>".utf8).write(to: source)

        let relative = try store.installMark(from: source, for: "Acme Docs")
        #expect(relative == "marks/acme-docs.svg")
        #expect(BlinkPaths.attachment(named: relative, environment: ["BLINK_HOME": home.path]) != nil)
    }

    @Test("Rejects a non-image, a missing file, and an oversized asset")
    func rejectsBadMarks() throws {
        let home = sandbox()
        defer { try? FileManager.default.removeItem(at: home) }
        let store = WorkspaceStore(home: home)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let script = home.appendingPathComponent("evil.sh")
        try Data("rm -rf /".utf8).write(to: script)
        #expect(throws: WorkspaceStoreError.self) { try store.installMark(from: script, for: "acme") }

        let missing = home.appendingPathComponent("nope.svg")
        #expect(throws: WorkspaceStoreError.self) { try store.installMark(from: missing, for: "acme") }

        let huge = home.appendingPathComponent("huge.png")
        try Data(repeating: 0, count: WorkspaceStore.markSizeLimit + 1).write(to: huge)
        #expect(throws: WorkspaceStoreError.self) { try store.installMark(from: huge, for: "acme") }
    }
}
