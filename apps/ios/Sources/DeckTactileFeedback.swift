import AVFoundation
import AudioToolbox
import UIKit

// MARK: - Tactile Feedback & Sound Synthesizer
//
// Replicates the Dieter Rams / Teenage Engineering mechanical desk controller
// sound and haptic model from the Lattices experiment page:
//   - Mechanical Key Switch Thock & Click (linear switch body + keycap noise)
//   - Rotary Encoder Ratchet Tick (1900Hz -> 300Hz detent click)
//   - Toggle Switch Clack (solid metal chassis latch)
//   - Push Button Pop (520Hz -> 120Hz smooth actuation)
//   - Approval Chime (dual-tone harmonic confirmation)
//   - Warning Buzz (needs-attention alert)
//
// Coupled with iOS Taptic Engine feedback generators:
//   - .rigid for mechanical switch key travel
//   - .heavy for accent / signature terracotta keys
//   - .medium for toggle / latch actions
//   - .light for micro pops & controls
//   - .selectionChanged for rotary detents & channel selection
//   - .success / .warning for agent decision resolutions

public final class DeckTactileFeedback {
    public static let shared = DeckTactileFeedback()

    public var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "deck_sound_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "deck_sound_enabled") }
    }

    public var isHapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "deck_haptics_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "deck_haptics_enabled") }
    }

    // MARK: - Haptic Generators
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    // MARK: - Audio Players Pool
    private enum SoundType: String, CaseIterable {
        case mechanicalOrange = "mech_orange"
        case mechanicalCream = "mech_cream"
        case rotaryTick = "rotary_tick"
        case toggleClack = "toggle_clack"
        case buttonPop = "button_pop"
        case approvalChime = "approval_chime"
        case warningBuzz = "warning_buzz"
    }

    private var playerPools: [SoundType: [AVAudioPlayer]] = [:]
    private var poolIndices: [SoundType: Int] = [:]
    private var isAudioReady = false
    private let audioQueue = DispatchQueue(label: "dev.lattices.tactile.audio", qos: .userInteractive)

    private init() {
        prepareHaptics()
        audioQueue.async { [weak self] in
            self?.setupAudioSessionAndSynthesize()
        }
    }

    // MARK: - Public Haptic & Sound Triggers

    /// Trigger a mechanical keypress (sculpted mechanical switch thock + contact click).
    /// `isOrange`: Terracotta "L" keys have a deeper, weightier body (240Hz), cream keys are crisper (340Hz).
    public func mechanicalKey(isOrange: Bool = false, id: Int = 0) {
        if isHapticsEnabled {
            if isOrange {
                heavyImpact.impactOccurred()
            } else {
                rigidImpact.impactOccurred()
            }
        }
        if isSoundEnabled {
            playSound(isOrange ? .mechanicalOrange : .mechanicalCream)
        }
    }

    /// Convenience for command tiles and keys.
    public func tilePress(isAccent: Bool = false) {
        mechanicalKey(isOrange: isAccent)
    }

    /// Stepping channels, cycling layers, or rotating encoder dials.
    public func rotaryTick() {
        if isHapticsEnabled {
            selectionFeedback.selectionChanged()
        }
        if isSoundEnabled {
            playSound(.rotaryTick)
        }
    }

    /// Physical toggle switches or transport mode changes.
    public func toggleClack() {
        if isHapticsEnabled {
            mediumImpact.impactOccurred()
        }
        if isSoundEnabled {
            playSound(.toggleClack)
        }
    }

    /// Standard micro button clicks (tabs, chips, icon buttons).
    public func buttonPop() {
        if isHapticsEnabled {
            lightImpact.impactOccurred()
        }
        if isSoundEnabled {
            playSound(.buttonPop)
        }
    }

    /// Autonomous agent decision approved (e.g. schema migration authorized).
    public func decisionApproved() {
        if isHapticsEnabled {
            notificationFeedback.notificationOccurred(.success)
        }
        if isSoundEnabled {
            playSound(.approvalChime)
        }
    }

    /// Decision deferred or rejected (e.g. ask me later / held).
    public func decisionDeferred() {
        if isHapticsEnabled {
            notificationFeedback.notificationOccurred(.warning)
        }
        if isSoundEnabled {
            playSound(.warningBuzz)
        }
    }

    // MARK: - Preparation & Warm-up

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

    // MARK: - Sound Synthesis & Playback

    private func playSound(_ type: SoundType) {
        audioQueue.async { [weak self] in
            guard let self, self.isAudioReady, let pool = self.playerPools[type], !pool.isEmpty else { return }
            let index = self.poolIndices[type, default: 0]
            let player = pool[index % pool.count]
            self.poolIndices[type] = (index + 1) % pool.count
            player.currentTime = 0
            player.play()
        }
    }

    private func setupAudioSessionAndSynthesize() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio session setup failed; sound will degrade gracefully
        }

        let sampleRate = 44100
        let poolSize = 3 // 3 overlapping voices per sound for zero cutoff on rapid taps

        for sound in SoundType.allCases {
            let samples = generateSamples(for: sound, sampleRate: sampleRate)
            let wavData = makeWavData(samples: samples, sampleRate: sampleRate)
            var players: [AVAudioPlayer] = []
            for _ in 0..<poolSize {
                if let player = try? AVAudioPlayer(data: wavData) {
                    player.prepareToPlay()
                    player.volume = 0.85
                    players.append(player)
                }
            }
            playerPools[sound] = players
        }

        isAudioReady = true
    }

    // MARK: - Procedural Waveform Synthesizer (Matching Experiment Page)

    private func generateSamples(for type: SoundType, sampleRate: Int) -> [Float] {
        switch type {
        case .mechanicalOrange:
            // Terracotta "L" signature key: deeper 240Hz body + 8ms noise switch contact
            return synthesizeMechanicalKey(baseFreq: 240.0, filterCutoff: 1200.0, sampleRate: sampleRate)

        case .mechanicalCream:
            // Cream bone-white key: crisper 340Hz body + 8ms noise switch contact
            return synthesizeMechanicalKey(baseFreq: 340.0, filterCutoff: 1800.0, sampleRate: sampleRate)

        case .rotaryTick:
            // 1900Hz -> 300Hz rapid exponential sweep in 15ms
            let count = Int(0.020 * Double(sampleRate))
            var samples = [Float]()
            var phase: Float = 0
            for i in 0..<count {
                let t = Float(i) / Float(sampleRate)
                let freq = 1900.0 * pow(300.0 / 1900.0, min(1.0, t / 0.015))
                phase += 2.0 * Float.pi * freq / Float(sampleRate)
                let wave = sin(phase)
                let gain = 0.22 * pow(0.001 / 0.22, min(1.0, t / 0.016))
                samples.append(wave * gain)
            }
            return samples

        case .toggleClack:
            // 450Hz -> 90Hz square-wave metal latch in 35ms
            let count = Int(0.045 * Double(sampleRate))
            var samples = [Float]()
            var phase: Float = 0
            for i in 0..<count {
                let t = Float(i) / Float(sampleRate)
                let freq = 450.0 * pow(90.0 / 450.0, min(1.0, t / 0.035))
                phase += 2.0 * Float.pi * freq / Float(sampleRate)
                let square = sin(phase) >= 0 ? 0.7 : -0.7
                let gain = 0.24 * pow(0.001 / 0.24, min(1.0, t / 0.040))
                samples.append(Float(square) * gain)
            }
            return samples

        case .buttonPop:
            // 520Hz -> 120Hz triangle pop in 25ms
            let count = Int(0.035 * Double(sampleRate))
            var samples = [Float]()
            var phase: Float = 0
            for i in 0..<count {
                let t = Float(i) / Float(sampleRate)
                let freq = 520.0 * pow(120.0 / 520.0, min(1.0, t / 0.025))
                phase += 2.0 * Float.pi * freq / Float(sampleRate)
                let tri = 2.0 * abs(2.0 * (phase / (2.0 * Float.pi) - floor(phase / (2.0 * Float.pi) + 0.5))) - 1.0
                let gain = 0.20 * pow(0.001 / 0.20, min(1.0, t / 0.030))
                samples.append(tri * gain)
            }
            return samples

        case .approvalChime:
            // Ascending dual-tone harmonic confirmation (587Hz -> 880Hz)
            let count = Int(0.120 * Double(sampleRate))
            var samples = [Float]()
            var phase1: Float = 0
            var phase2: Float = 0
            for i in 0..<count {
                let t = Float(i) / Float(sampleRate)
                phase1 += 2.0 * Float.pi * 587.33 / Float(sampleRate)
                phase2 += 2.0 * Float.pi * 880.00 / Float(sampleRate)
                let wave1 = sin(phase1)
                let wave2 = sin(phase2)
                let gain1 = t < 0.06 ? (0.22 * (1.0 - t / 0.06)) : 0.0
                let gain2 = t >= 0.03 ? (0.26 * (1.0 - (t - 0.03) / 0.09)) : 0.0
                samples.append(wave1 * gain1 + wave2 * gain2)
            }
            return samples

        case .warningBuzz:
            // Crisp double-pulse alert for needs-attention / defer
            let count = Int(0.080 * Double(sampleRate))
            var samples = [Float]()
            var phase: Float = 0
            for i in 0..<count {
                let t = Float(i) / Float(sampleRate)
                phase += 2.0 * Float.pi * 220.0 / Float(sampleRate)
                let wave = sin(phase)
                let envelope: Float
                if t < 0.035 {
                    envelope = 0.22 * (1.0 - t / 0.035)
                } else if t < 0.045 {
                    envelope = 0.0
                } else {
                    envelope = 0.20 * (1.0 - (t - 0.045) / 0.035)
                }
                samples.append(wave * envelope)
            }
            return samples
        }
    }

    private func synthesizeMechanicalKey(baseFreq: Float, filterCutoff: Float, sampleRate: Int) -> [Float] {
        let count = Int(0.065 * Double(sampleRate))
        var samples = [Float]()
        var phase: Float = 0
        var filtered: Float = 0
        let fEnd: Float = 55.0

        for i in 0..<count {
            let t = Float(i) / Float(sampleRate)
            // Frequency drops exponentially to 55Hz
            let freq = baseFreq * pow(fEnd / baseFreq, min(1.0, t / 0.055))
            phase += 2.0 * Float.pi * freq / Float(sampleRate)

            // Triangle wave oscillator
            let tri = 2.0 * abs(2.0 * (phase / (2.0 * Float.pi) - floor(phase / (2.0 * Float.pi) + 0.5))) - 1.0

            // One-pole lowpass filter sweeping to 300Hz
            let cutoff = filterCutoff * pow(300.0 / filterCutoff, min(1.0, t / 0.050))
            let rc = 1.0 / (2.0 * Float.pi * cutoff)
            let dt = 1.0 / Float(sampleRate)
            let alpha = dt / (rc + dt)
            filtered = filtered + alpha * (tri - filtered)

            // Gain envelope
            let gain = 0.32 * pow(0.001 / 0.32, min(1.0, t / 0.060))

            // Short 8ms key switch contact click noise
            let noise: Float
            if t < 0.008 {
                let noiseGain = 0.14 * (1.0 - t / 0.008)
                noise = Float.random(in: -1.0...1.0) * noiseGain
            } else {
                noise = 0
            }

            samples.append(filtered * gain + noise)
        }
        return samples
    }

    // MARK: - WAV Encoder

    private func makeWavData(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let numSamples = samples.count
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample) / 8)
        let blockAlign = UInt16(numChannels * bitsPerSample / 8)
        let subchunk2Size = UInt32(numSamples * Int(numChannels) * 2)
        let chunkSize = 36 + subchunk2Size

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSizeLE = chunkSize.littleEndian
        data.append(Data(bytes: &chunkSizeLE, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = numChannels.littleEndian
        data.append(Data(bytes: &channels, count: 2))
        var sRate = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sRate, count: 4))
        var bRate = byteRate.littleEndian
        data.append(Data(bytes: &bRate, count: 4))
        var bAlign = blockAlign.littleEndian
        data.append(Data(bytes: &bAlign, count: 2))
        var bps = bitsPerSample.littleEndian
        data.append(Data(bytes: &bps, count: 2))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var s2Size = subchunk2Size.littleEndian
        data.append(Data(bytes: &s2Size, count: 4))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var intSample = Int16(clamped * 32767.0).littleEndian
            data.append(Data(bytes: &intSample, count: 2))
        }
        return data
    }
}
