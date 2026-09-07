import XCTest
@testable import DeckKit

final class DeckTactileTests: XCTestCase {
    func testBuiltinCatalogLoads() {
        let catalog = DeckTactileTheme.loadBuiltinCatalog()
        XCTAssertEqual(catalog.version, 1)
        XCTAssertFalse(catalog.sounds.isEmpty)
        XCTAssertFalse(catalog.events.isEmpty)
        XCTAssertNotNil(catalog.sounds["buttonPop"])
        XCTAssertNotNil(catalog.events[DeckTactileEventID.deckButton.rawValue])
    }

    func testResolveEventWithParams() throws {
        let theme = DeckTactileTheme()
        let resolved = theme.resolve(eventID: "deck.key.accent", params: ["id": .int(2)])
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.haptic, .heavy)
        XCTAssertEqual(resolved?.params["id"]?.intValue, 2)
    }

    func testSynthesizerProducesNonSilentWAV() throws {
        let catalog = DeckTactileTheme.loadBuiltinCatalog()
        let patch = try XCTUnwrap(catalog.sounds["buttonPop"])
        let wav = DeckTactileSynthesizer.renderWAV(patch: patch)
        XCTAssertGreaterThan(wav.count, 44)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
    }

    func testMergeOverlayReplacesSounds() throws {
        let theme = DeckTactileTheme()
        let overlay = DeckTactileCatalog(
            version: 1,
            sounds: [
                "buttonPop": DeckSoundPatch(
                    duration: 0.01,
                    layers: [
                        .oscillator(
                            DeckOscillatorLayer(
                                waveform: .sine,
                                frequency: DeckFrequencySpec(start: .fixed(440)),
                                gain: .envelope(DeckEnvelope(start: 0.1, end: 0.0, time: 0.01))
                            )
                        )
                    ]
                )
            ],
            events: [:]
        )
        theme.merge(overlay)
        let merged = theme.currentCatalog().sounds["buttonPop"]
        XCTAssertEqual(merged?.duration, 0.01)
    }
}
