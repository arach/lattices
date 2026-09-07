import Foundation

public struct DeckTactileRenderOptions: Equatable, Sendable {
    public var sampleRate: Int
    public var params: [String: DeckTactileParamValue]

    public init(sampleRate: Int = 44_100, params: [String: DeckTactileParamValue] = [:]) {
        self.sampleRate = sampleRate
        self.params = params
    }
}

public enum DeckTactileSynthesizer {
    public static func render(patch: DeckSoundPatch, options: DeckTactileRenderOptions = DeckTactileRenderOptions()) -> [Float] {
        let sampleRate = options.sampleRate
        let sampleCount = max(1, Int(patch.duration * Double(sampleRate)))
        var buffer = [Float](repeating: 0, count: sampleCount)

        for layer in patch.layers {
            switch layer {
            case .oscillator(let osc):
                renderOscillator(osc, into: &buffer, sampleRate: sampleRate, params: options.params)
            case .noise(let noise):
                renderNoise(noise, into: &buffer, sampleRate: sampleRate, params: options.params)
            }
        }

        let volume = Float(patch.volume ?? 1.0)
        if volume != 1 {
            for index in buffer.indices {
                buffer[index] *= volume
            }
        }
        return buffer
    }

    public static func renderWAV(patch: DeckSoundPatch, options: DeckTactileRenderOptions = DeckTactileRenderOptions()) -> Data {
        let samples = render(patch: patch, options: options)
        return encodeWAV(samples: samples, sampleRate: options.sampleRate)
    }

    // MARK: - Layers

    private static func renderOscillator(
        _ layer: DeckOscillatorLayer,
        into buffer: inout [Float],
        sampleRate: Int,
        params: [String: DeckTactileParamValue]
    ) {
        let envelopes = envelopes(for: layer.gain)
        var phase: Float = 0
        var filtered: Float = 0

        for index in buffer.indices {
            let time = Float(index) / Float(sampleRate)
            let frequency = frequency(at: time, spec: layer.frequency, params: params)
            phase += 2 * Float.pi * frequency / Float(sampleRate)
            let wave = waveformValue(layer.waveform, phase: phase)

            var sample = wave
            if let filter = layer.filter {
                let cutoff = interpolate(
                    start: Float(filter.start),
                    end: Float(filter.end),
                    time: time,
                    duration: Float(filter.time),
                    curve: filter.curve ?? .exponential
                )
                let rc = 1 / (2 * Float.pi * max(cutoff, 1))
                let dt = 1 / Float(sampleRate)
                let alpha = dt / (rc + dt)
                filtered += alpha * (wave - filtered)
                sample = filtered
            }

            let gain = envelopeGain(at: time, envelopes: envelopes)
            buffer[index] += sample * gain
        }
    }

    private static func renderNoise(
        _ layer: DeckNoiseLayer,
        into buffer: inout [Float],
        sampleRate: Int,
        params: [String: DeckTactileParamValue]
    ) {
        let envelopes = envelopes(for: layer.gain)
        let count = min(buffer.count, Int(layer.duration * Double(sampleRate)))
        for index in 0..<count {
            let time = Float(index) / Float(sampleRate)
            let gain = envelopeGain(at: time, envelopes: envelopes)
            buffer[index] += Float.random(in: -1...1) * gain
        }
    }

    // MARK: - Envelopes & frequency

    private static func envelopes(for spec: DeckGainSpec) -> [DeckEnvelope] {
        switch spec {
        case .envelope(let envelope):
            return [envelope]
        case .segments(let segments):
            return segments
        }
    }

    private static func envelopeGain(at time: Float, envelopes: [DeckEnvelope]) -> Float {
        var total: Float = 0
        for envelope in envelopes {
            let delay = Float(envelope.delay ?? 0)
            let local = time - delay
            guard local >= 0 else { continue }
            let duration = max(Float(envelope.time), 0.0001)
            let progress = min(1, local / duration)
            let gain = interpolate(
                start: Float(envelope.start),
                end: Float(envelope.end),
                progress: progress,
                curve: envelope.curve ?? .linear
            )
            total += gain
        }
        return total
    }

    private static func frequency(
        at time: Float,
        spec: DeckFrequencySpec,
        params: [String: DeckTactileParamValue]
    ) -> Float {
        let start = resolvedFrequency(spec.start, params: params)
        guard let end = spec.end, let duration = spec.time, duration > 0 else {
            return start
        }
        return interpolate(
            start: start,
            end: Float(end),
            time: time,
            duration: Float(duration),
            curve: spec.curve ?? .exponential
        )
    }

    private static func resolvedFrequency(_ value: DeckFrequencyValue, params: [String: DeckTactileParamValue]) -> Float {
        switch value {
        case .fixed(let hz):
            return Float(hz)
        case .parameterized(let base, let detune):
            let raw = params[detune.param]?.intValue ?? 0
            let mod = detune.modulo > 0 ? raw % detune.modulo : raw
            return Float(base + Double(mod) * detune.step)
        }
    }

    private static func interpolate(
        start: Float,
        end: Float,
        time: Float,
        duration: Float,
        curve: DeckCurve
    ) -> Float {
        let progress = min(1, max(0, time / max(duration, 0.0001)))
        return interpolate(start: start, end: end, progress: progress, curve: curve)
    }

    private static func interpolate(start: Float, end: Float, progress: Float, curve: DeckCurve) -> Float {
        switch curve {
        case .linear:
            return start + (end - start) * progress
        case .exponential:
            guard start > 0, end > 0 else {
                return start + (end - start) * progress
            }
            let ratio = end / start
            return start * pow(ratio, progress)
        }
    }

    private static func waveformValue(_ waveform: DeckWaveform, phase: Float) -> Float {
        switch waveform {
        case .sine:
            return sin(phase)
        case .triangle:
            let normalized = phase / (2 * Float.pi)
            return 2 * abs(2 * (normalized - floor(normalized + 0.5))) - 1
        case .square:
            return sin(phase) >= 0 ? 0.7 : -0.7
        }
    }

    // MARK: - WAV

    public static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let numSamples = samples.count
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample) / 8)
        let blockAlign = UInt16(numChannels * bitsPerSample / 8)
        let subchunk2Size = UInt32(numSamples * Int(numChannels) * 2)
        let chunkSize = 36 + subchunk2Size

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        var chunkSizeLE = chunkSize.littleEndian
        data.append(Data(bytes: &chunkSizeLE, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
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
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        var s2Size = subchunk2Size.littleEndian
        data.append(Data(bytes: &s2Size, count: 4))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var intSample = Int16(clamped * 32767).littleEndian
            data.append(Data(bytes: &intSample, count: 2))
        }
        return data
    }
}
