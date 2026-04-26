import XCTest
@testable import DeckKit

final class DeckKitTests: XCTestCase {
    func testManifestRoundTripPreservesEmbeddedSecurity() throws {
        let manifest = DeckManifest(
            product: DeckProductIdentity(
                id: "com.arach.lattices",
                displayName: "Lattices Companion",
                owner: "lattices"
            ),
            security: .embeddedDelegated(owner: "talkie"),
            capabilities: [.voiceAgent, .layoutControl, .embeddedSecurityDelegation],
            pages: [
                DeckPage(
                    id: "voice",
                    title: "Voice",
                    iconSystemName: "mic.fill",
                    kind: .voice,
                    accentToken: "royal-blue"
                )
            ]
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(DeckManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.security.delegatedOwner, "talkie")
    }

    func testSecurityConvenienceProfilesMatchIntendedModes() {
        let standalone = DeckSecurityConfiguration.standaloneBonjour()
        XCTAssertEqual(standalone.mode, .standalone)
        XCTAssertEqual(standalone.pairingStrategy, .bonjour)
        XCTAssertTrue(standalone.requestSigningRequired)
        XCTAssertTrue(standalone.payloadEncryptionRequired)
        XCTAssertNil(standalone.delegatedOwner)

        let embedded = DeckSecurityConfiguration.embeddedDelegated(owner: "talkie")
        XCTAssertEqual(embedded.mode, .embedded)
        XCTAssertEqual(embedded.pairingStrategy, .delegated)
        XCTAssertTrue(embedded.payloadEncryptionRequired)
        XCTAssertEqual(embedded.delegatedOwner, "talkie")
    }

    func testPairingPayloadRoundTripPreservesSecurityFlags() throws {
        let response = DeckPairingResponse(
            disposition: .approved,
            bridgeName: "Lats Bridge",
            bridgePublicKey: "bridge-public-key",
            bridgeFingerprint: "ABCD-1234",
            requestSigningRequired: true,
            payloadEncryptionRequired: true,
            detail: "Trusted on the Mac."
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DeckPairingResponse.self, from: data)

        XCTAssertEqual(decoded, response)
    }

    func testRuntimeSnapshotRoundTripPreservesSwitcherAndHistory() throws {
        let snapshot = DeckRuntimeSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_713_700_000),
            cockpit: DeckCockpitState(
                title: "Command Deck",
                detail: "Quick controls from your Mac-defined cockpit.",
                pages: [
                    DeckCockpitPage(
                        id: "main",
                        title: "Main",
                        subtitle: "Core controls",
                        columns: 4,
                        tiles: [
                            DeckCockpitTile(
                                id: "main-0",
                                shortcutID: "voice-toggle",
                                title: "Voice",
                                subtitle: "Start listening",
                                iconSystemName: "mic.fill",
                                accentToken: "voice",
                                actionID: "voice.toggle",
                                isActive: true
                            )
                        ]
                    )
                ]
            ),
            trackpad: DeckTrackpadState(
                isEnabled: true,
                isAvailable: true,
                statusTitle: "Trackpad Ready",
                statusDetail: "Use the surface to move the Mac pointer.",
                pointerScale: 1.8,
                scrollScale: 1.2,
                supportsDragLock: true
            ),
            voice: DeckVoiceState(
                phase: .reasoning,
                transcript: "Arrange my review setup",
                responseSummary: "Preparing a code review layout.",
                provider: "vox"
            ),
            desktop: DeckDesktopSummary(
                activeLayerName: "review",
                activeAppName: "Safari",
                screenCount: 2,
                visibleWindowCount: 6,
                sessionCount: 3
            ),
            layout: DeckLayoutState(
                screenName: "Built-in Retina Display",
                frontmostWindow: DeckLayoutFocusWindow(
                    id: "window:42",
                    itemID: "window:42",
                    appName: "Safari",
                    title: "Pull request",
                    frame: DeckRect(x: 40, y: 80, w: 1440, h: 900),
                    normalizedFrame: DeckRect(x: 0.0, y: 0.0, w: 0.75, h: 1.0),
                    placement: "left"
                ),
                preview: DeckLayoutPreview(
                    aspectRatio: 1.6,
                    windows: [
                        DeckLayoutPreviewWindow(
                            id: "window:42",
                            itemID: "window:42",
                            title: "Pull request",
                            subtitle: "Safari",
                            normalizedFrame: DeckRect(x: 0.0, y: 0.0, w: 0.75, h: 1.0),
                            isFrontmost: true
                        )
                    ]
                )
            ),
            switcher: DeckSwitcherState(items: [
                DeckSwitcherItem(
                    id: "app:safari",
                    title: "Safari",
                    subtitle: "Pull request",
                    iconToken: "safari",
                    kind: .application,
                    isFrontmost: true
                ),
                DeckSwitcherItem(
                    id: "session:frontend-a1b2c3",
                    title: "frontend-a1b2c3",
                    subtitle: "tmux session",
                    iconToken: "terminal",
                    kind: .session
                )
            ]),
            history: [
                DeckHistoryEntry(
                    id: "history-1",
                    title: "Grid layout applied",
                    detail: "Distributed four visible windows.",
                    kind: .layout,
                    undoActionID: "undo-grid-layout"
                )
            ],
            questions: [
                DeckQuestionCard(
                    id: "question-1",
                    prompt: "Which monitor should hold the terminals?",
                    options: [
                        DeckQuestionOption(
                            id: "primary",
                            title: "Primary display",
                            actionID: "layout.place-terminals-primary"
                        )
                    ]
                )
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DeckRuntimeSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.cockpit?.pages.first?.tiles.first?.shortcutID, "voice-toggle")
        XCTAssertEqual(decoded.trackpad?.statusTitle, "Trackpad Ready")
        XCTAssertEqual(decoded.voice?.provider, "vox")
        XCTAssertEqual(decoded.layout?.frontmostWindow?.placement, "left")
        XCTAssertEqual(decoded.switcher?.items.count, 2)
    }
}
