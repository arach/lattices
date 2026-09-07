import Foundation

public struct DeckTactileResolvedEvent: Equatable, Sendable {
    public var eventID: String
    public var patch: DeckSoundPatch?
    public var haptic: DeckHapticStyle?
    public var params: [String: DeckTactileParamValue]

    public init(
        eventID: String,
        patch: DeckSoundPatch? = nil,
        haptic: DeckHapticStyle? = nil,
        params: [String: DeckTactileParamValue] = [:]
    ) {
        self.eventID = eventID
        self.patch = patch
        self.haptic = haptic
        self.params = params
    }
}

public final class DeckTactileTheme: @unchecked Sendable {
    public static let shared = DeckTactileTheme()

    private var catalog: DeckTactileCatalog
    private let lock = NSLock()

    public init(catalog: DeckTactileCatalog = DeckTactileTheme.loadBuiltinCatalog()) {
        self.catalog = catalog
    }

    public func currentCatalog() -> DeckTactileCatalog {
        lock.lock()
        defer { lock.unlock() }
        return catalog
    }

    /// Replace the active catalog wholesale (e.g. after loading a custom theme file).
    public func replaceCatalog(_ catalog: DeckTactileCatalog) {
        lock.lock()
        self.catalog = catalog
        lock.unlock()
    }

    /// Merge sounds/events from an overlay catalog. Existing keys are replaced.
    public func merge(_ overlay: DeckTactileCatalog) {
        lock.lock()
        catalog.sounds.merge(overlay.sounds) { _, new in new }
        catalog.events.merge(overlay.events) { _, new in new }
        if let meta = overlay.meta {
            catalog.meta = meta
        }
        if overlay.version > 0 {
            catalog.version = overlay.version
        }
        lock.unlock()
    }

    public func resolve(
        eventID: String,
        params: [String: DeckTactileParamValue] = [:]
    ) -> DeckTactileResolvedEvent? {
        lock.lock()
        let binding = catalog.events[eventID]
        let sounds = catalog.sounds
        lock.unlock()

        guard let binding else { return nil }

        var mergedParams = params
        var patchID: String?
        if let sound = binding.sound {
            patchID = sound.patchID
            for (key, value) in sound.params {
                mergedParams[key] = value
            }
        }

        let patch = patchID.flatMap { sounds[$0] }
        let soundPatch = binding.hapticOnly == true ? nil : patch
        let hapticStyle = binding.soundOnly == true ? nil : binding.haptic

        return DeckTactileResolvedEvent(
            eventID: eventID,
            patch: soundPatch,
            haptic: hapticStyle,
            params: mergedParams
        )
    }

    public func resolve(_ event: DeckTactileEventID, params: [String: DeckTactileParamValue] = [:]) -> DeckTactileResolvedEvent? {
        resolve(eventID: event.rawValue, params: params)
    }

    public func renderWAV(
        eventID: String,
        params: [String: DeckTactileParamValue] = [:],
        sampleRate: Int = 44_100
    ) -> Data? {
        guard let resolved = resolve(eventID: eventID, params: params),
              let patch = resolved.patch else { return nil }
        return DeckTactileSynthesizer.renderWAV(
            patch: patch,
            options: DeckTactileRenderOptions(sampleRate: sampleRate, params: resolved.params)
        )
    }

    public static func loadBuiltinCatalog() -> DeckTactileCatalog {
        if let url = Bundle.module.url(forResource: "deck-tactile-catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(DeckTactileCatalog.self, from: data) {
            return catalog
        }
        return DeckTactileCatalog()
    }

    public static func loadCatalog(from url: URL) throws -> DeckTactileCatalog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DeckTactileCatalog.self, from: data)
    }

    public static func loadCatalog(fromJSON data: Data) throws -> DeckTactileCatalog {
        try JSONDecoder().decode(DeckTactileCatalog.self, from: data)
    }
}
