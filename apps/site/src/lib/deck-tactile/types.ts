export type DeckCurve = 'linear' | 'exponential'

export type DeckWaveform = 'sine' | 'triangle' | 'square'

export type DeckHapticStyle =
  | 'rigid'
  | 'heavy'
  | 'medium'
  | 'light'
  | 'selection'
  | 'success'
  | 'warning'
  | 'generic'
  | 'alignment'

export type DeckTactileParamValue = boolean | number | string

export interface DeckEnvelope {
  start: number
  end: number
  time: number
  curve?: DeckCurve
  delay?: number
}

export type DeckGainSpec = DeckEnvelope | { segments: DeckEnvelope[] }

export type DeckFrequencyValue =
  | number
  | { base: number; detune: { param: string; step: number; modulo: number } }

export interface DeckFrequencySpec {
  start: DeckFrequencyValue
  end?: number
  time?: number
  curve?: DeckCurve
}

export interface DeckFilterSpec {
  type: string
  start: number
  end: number
  time: number
  curve?: DeckCurve
}

export interface DeckOscillatorLayer {
  kind: 'oscillator'
  waveform: DeckWaveform
  frequency: DeckFrequencySpec
  gain: DeckGainSpec
  filter?: DeckFilterSpec
}

export interface DeckNoiseLayer {
  kind: 'noise'
  duration: number
  gain: DeckGainSpec
}

export type DeckSoundLayer = DeckOscillatorLayer | DeckNoiseLayer

export interface DeckSoundPatch {
  duration: number
  volume?: number
  layers: DeckSoundLayer[]
}

export type DeckTactileSoundRef =
  | string
  | { ref: string; params?: Record<string, DeckTactileParamValue> }

export interface DeckTactileEventBinding {
  sound?: DeckTactileSoundRef
  haptic?: DeckHapticStyle
  hapticOnly?: boolean
  soundOnly?: boolean
}

export interface DeckTactileCatalog {
  version: number
  meta?: { name?: string; description?: string }
  sounds: Record<string, DeckSoundPatch>
  events: Record<string, DeckTactileEventBinding>
}

export type DeckTactileEventID =
  | 'deck.key'
  | 'deck.key.accent'
  | 'deck.rotary'
  | 'deck.toggle'
  | 'deck.button'
  | 'deck.decision.approved'
  | 'deck.decision.deferred'
  | 'pointer.aim'
  | 'pointer.commit'
