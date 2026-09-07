import AVFoundation
import DeckKit
import UIKit

// MARK: - Catalog-driven tactile feedback (iOS)
//
// Sound patches and event bindings live in `deck-tactile-catalog.json` (DeckKit).
// Customize by merging a JSON overlay: `DeckTactileFeedback.shared.loadTheme(from:)`.

public final class DeckTactileFeedback {
    public static let shared = DeckTactileFeedback()

    public var theme: DeckTactileTheme { DeckTactileTheme.shared }

    public var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "deck_sound_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "deck_sound_enabled") }
    }

    public var isHapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "deck_haptics_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "deck_haptics_enabled") }
    }

    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private var playerPools: [String: [AVAudioPlayer]] = [:]
    private var poolIndices: [String: Int] = [:]
    private var isAudioReady = false
    private let audioQueue = DispatchQueue(label: "dev.lattices.tactile.audio", qos: .userInteractive)
    private let sampleRate = 44_100
    private let poolSize = 3

    private init() {
        prepareHaptics()
        audioQueue.async { [weak self] in
            self?.setupAudioSessionAndWarmPools()
        }
    }

    // MARK: - Theme loading

    public func loadTheme(from url: URL) throws {
        let catalog = try DeckTactileTheme.loadCatalog(from: url)
        theme.replaceCatalog(catalog)
        audioQueue.async { [weak self] in
            self?.rebuildPools()
        }
    }

    public func mergeTheme(from url: URL) throws {
        let overlay = try DeckTactileTheme.loadCatalog(from: url)
        theme.merge(overlay)
        audioQueue.async { [weak self] in
            self?.rebuildPools()
        }
    }

    // MARK: - Event playback

    public func play(
        _ event: DeckTactileEventID,
        params: [String: DeckTactileParamValue] = [:]
    ) {
        play(eventID: event.rawValue, params: params)
    }

    public func play(
        eventID: String,
        params: [String: DeckTactileParamValue] = [:]
    ) {
        guard let resolved = theme.resolve(eventID: eventID, params: params) else { return }

        if isHapticsEnabled, let haptic = resolved.haptic {
            performHaptic(haptic)
        }
        if isSoundEnabled, let patch = resolved.patch {
            playPatch(patch, cacheKey: cacheKey(for: resolved), params: resolved.params)
        }
    }

    // MARK: - Legacy convenience (maps to catalog events)

    public func mechanicalKey(isOrange: Bool = false, id: Int = 0) {
        let event: DeckTactileEventID = isOrange ? .deckKeyAccent : .deckKey
        play(event, params: ["id": .int(id)])
    }

    public func tilePress(isAccent: Bool = false) {
        mechanicalKey(isOrange: isAccent)
    }

    public func rotaryTick() { play(.deckRotary) }
    public func toggleClack() { play(.deckToggle) }
    public func buttonPop() { play(.deckButton) }
    public func decisionApproved() { play(.deckDecisionApproved) }
    public func decisionDeferred() { play(.deckDecisionDeferred) }

    public func prepareHaptics() {
        DispatchQueue.main.async { [weak self] in
            self?.rigidImpact.prepare()
            self?.mediumImpact.prepare()
            self?.heavyImpact.prepare()
            self?.lightImpact.prepare()
            self?.selectionFeedback.prepare()
            self?.notificationFeedback.prepare()
        }
    }

    // MARK: - Audio

    private func setupAudioSessionAndWarmPools() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // degrade gracefully
        }
        rebuildPools()
        isAudioReady = true
    }

    private func rebuildPools() {
        playerPools.removeAll()
        poolIndices.removeAll()
        let catalog = theme.currentCatalog()
        for (patchID, patch) in catalog.sounds {
            let wav = DeckTactileSynthesizer.renderWAV(
                patch: patch,
                options: DeckTactileRenderOptions(sampleRate: sampleRate)
            )
            playerPools[patchID] = makePlayers(from: wav)
            poolIndices[patchID] = 0
        }
    }

    private func playPatch(
        _ patch: DeckSoundPatch,
        cacheKey: String,
        params: [String: DeckTactileParamValue]
    ) {
        audioQueue.async { [weak self] in
            guard let self, self.isAudioReady else { return }

            if params.isEmpty, let pool = self.playerPools[cacheKey], !pool.isEmpty {
                self.playFromPool(cacheKey: cacheKey, pool: pool)
                return
            }

            let wav = DeckTactileSynthesizer.renderWAV(
                patch: patch,
                options: DeckTactileRenderOptions(sampleRate: self.sampleRate, params: params)
            )
            if let player = try? AVAudioPlayer(data: wav) {
                player.prepareToPlay()
                player.volume = Float(patch.volume ?? 0.85)
                player.play()
            }
        }
    }

    private func playFromPool(cacheKey: String, pool: [AVAudioPlayer]) {
        let index = poolIndices[cacheKey, default: 0]
        let player = pool[index % pool.count]
        poolIndices[cacheKey] = (index + 1) % pool.count
        player.currentTime = 0
        player.play()
    }

    private func makePlayers(from wav: Data) -> [AVAudioPlayer] {
        var players: [AVAudioPlayer] = []
        for _ in 0..<poolSize {
            if let player = try? AVAudioPlayer(data: wav) {
                player.prepareToPlay()
                player.volume = 0.85
                players.append(player)
            }
        }
        return players
    }

    private func cacheKey(for resolved: DeckTactileResolvedEvent) -> String {
        if let sound = theme.currentCatalog().events[resolved.eventID]?.sound {
            return sound.patchID
        }
        return resolved.eventID
    }

    private func performHaptic(_ style: DeckHapticStyle) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch style {
            case .rigid:
                self.rigidImpact.impactOccurred()
            case .heavy:
                self.heavyImpact.impactOccurred()
            case .medium:
                self.mediumImpact.impactOccurred()
            case .light:
                self.lightImpact.impactOccurred()
            case .selection:
                self.selectionFeedback.selectionChanged()
            case .success:
                self.notificationFeedback.notificationOccurred(.success)
            case .warning:
                self.notificationFeedback.notificationOccurred(.warning)
            case .generic, .alignment:
                self.lightImpact.impactOccurred()
            }
        }
    }
}
