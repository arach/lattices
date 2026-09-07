import type {
  DeckCurve,
  DeckEnvelope,
  DeckFrequencySpec,
  DeckFrequencyValue,
  DeckGainSpec,
  DeckOscillatorLayer,
  DeckSoundPatch,
  DeckTactileParamValue,
  DeckWaveform,
} from './types'

export interface RenderOptions {
  sampleRate?: number
  params?: Record<string, DeckTactileParamValue>
}

function envelopes(spec: DeckGainSpec): DeckEnvelope[] {
  if ('segments' in spec) return spec.segments
  return [spec]
}

function paramInt(params: Record<string, DeckTactileParamValue>, key: string): number {
  const value = params[key]
  if (typeof value === 'number') return value
  if (typeof value === 'boolean') return value ? 1 : 0
  if (typeof value === 'string') return Number.parseInt(value, 10) || 0
  return 0
}

function resolvedFrequency(value: DeckFrequencyValue, params: Record<string, DeckTactileParamValue>): number {
  if (typeof value === 'number') return value
  const mod = value.detune.modulo > 0 ? paramInt(params, value.detune.param) % value.detune.modulo : paramInt(params, value.detune.param)
  return value.base + mod * value.detune.step
}

function interpolate(start: number, end: number, progress: number, curve: DeckCurve = 'linear'): number {
  const t = Math.min(1, Math.max(0, progress))
  if (curve === 'exponential' && start > 0 && end > 0) {
    return start * Math.pow(end / start, t)
  }
  return start + (end - start) * t
}

function envelopeGain(time: number, spec: DeckGainSpec): number {
  return envelopes(spec).reduce((total, envelope) => {
    const delay = envelope.delay ?? 0
    const local = time - delay
    if (local < 0) return total
    const progress = Math.min(1, local / Math.max(envelope.time, 0.0001))
    return total + interpolate(envelope.start, envelope.end, progress, envelope.curve ?? 'linear')
  }, 0)
}

function frequencyAt(time: number, spec: DeckFrequencySpec, params: Record<string, DeckTactileParamValue>): number {
  const start = resolvedFrequency(spec.start, params)
  if (spec.end == null || spec.time == null) return start
  const progress = Math.min(1, time / Math.max(spec.time, 0.0001))
  return interpolate(start, spec.end, progress, spec.curve ?? 'exponential')
}

function waveformValue(waveform: DeckWaveform, phase: number): number {
  if (waveform === 'sine') return Math.sin(phase)
  if (waveform === 'square') return Math.sin(phase) >= 0 ? 0.7 : -0.7
  const normalized = phase / (2 * Math.PI)
  return 2 * Math.abs(2 * (normalized - Math.floor(normalized + 0.5))) - 1
}

function renderOscillator(layer: DeckOscillatorLayer, buffer: Float32Array, sampleRate: number, params: Record<string, DeckTactileParamValue>) {
  let phase = 0
  let filtered = 0
  for (let index = 0; index < buffer.length; index += 1) {
    const time = index / sampleRate
    const freq = frequencyAt(time, layer.frequency, params)
    phase += (2 * Math.PI * freq) / sampleRate
    let sample = waveformValue(layer.waveform, phase)
    if (layer.filter) {
      const cutoff = interpolate(layer.filter.start, layer.filter.end, Math.min(1, time / Math.max(layer.filter.time, 0.0001)), layer.filter.curve ?? 'exponential')
      const rc = 1 / (2 * Math.PI * Math.max(cutoff, 1))
      const dt = 1 / sampleRate
      const alpha = dt / (rc + dt)
      filtered += alpha * (sample - filtered)
      sample = filtered
    }
    buffer[index] += sample * envelopeGain(time, layer.gain)
  }
}

function renderNoise(layer: { duration: number; gain: DeckGainSpec }, buffer: Float32Array, sampleRate: number) {
  const count = Math.min(buffer.length, Math.floor(layer.duration * sampleRate))
  for (let index = 0; index < count; index += 1) {
    const time = index / sampleRate
    buffer[index] += (Math.random() * 2 - 1) * envelopeGain(time, layer.gain)
  }
}

export function renderPatch(patch: DeckSoundPatch, options: RenderOptions = {}): Float32Array {
  const sampleRate = options.sampleRate ?? 44_100
  const params = options.params ?? {}
  const count = Math.max(1, Math.floor(patch.duration * sampleRate))
  const buffer = new Float32Array(count)
  for (const layer of patch.layers) {
    if (layer.kind === 'oscillator') renderOscillator(layer, buffer, sampleRate, params)
    else renderNoise(layer, buffer, sampleRate)
  }
  const volume = patch.volume ?? 1
  if (volume !== 1) {
    for (let i = 0; i < buffer.length; i += 1) buffer[i] *= volume
  }
  return buffer
}

export function playPatch(ctx: AudioContext, patch: DeckSoundPatch, params: Record<string, DeckTactileParamValue> = {}) {
  const t = ctx.currentTime
  for (const layer of patch.layers) {
    if (layer.kind === 'noise') {
      const noiseBuffer = ctx.createBuffer(1, Math.max(1, Math.floor(ctx.sampleRate * layer.duration)), ctx.sampleRate)
      const output = noiseBuffer.getChannelData(0)
      for (let i = 0; i < output.length; i += 1) output[i] = Math.random() * 2 - 1
      const noise = ctx.createBufferSource()
      noise.buffer = noiseBuffer
      const gain = ctx.createGain()
      const env = envelopes(layer.gain)[0]
      gain.gain.setValueAtTime(Math.max(env.start, 0.0001), t + (env.delay ?? 0))
      gain.gain.exponentialRampToValueAtTime(Math.max(env.end, 0.0001), t + (env.delay ?? 0) + env.time)
      noise.connect(gain)
      gain.connect(ctx.destination)
      noise.start(t + (env.delay ?? 0))
      continue
    }

    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    const filter = layer.filter ? ctx.createBiquadFilter() : null
    osc.type = layer.waveform
    const startFreq = resolvedFrequency(layer.frequency.start, params)
    osc.frequency.setValueAtTime(startFreq, t)
    if (layer.frequency.end != null && layer.frequency.time != null) {
      osc.frequency.exponentialRampToValueAtTime(Math.max(layer.frequency.end, 1), t + layer.frequency.time)
    }
    if (filter && layer.filter) {
      filter.type = 'lowpass'
      filter.frequency.setValueAtTime(layer.filter.start, t)
      filter.frequency.exponentialRampToValueAtTime(Math.max(layer.filter.end, 1), t + layer.filter.time)
    }
    for (const env of envelopes(layer.gain)) {
      gain.gain.setValueAtTime(Math.max(env.start, 0.0001), t + (env.delay ?? 0))
      gain.gain.exponentialRampToValueAtTime(Math.max(env.end, 0.0001), t + (env.delay ?? 0) + env.time)
    }
    if (filter) {
      osc.connect(filter)
      filter.connect(gain)
    } else {
      osc.connect(gain)
    }
    gain.connect(ctx.destination)
    osc.start(t)
    osc.stop(t + patch.duration + 0.01)
  }
}
