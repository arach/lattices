import catalogJSON from './catalog.json'
import type {
  DeckSoundPatch,
  DeckTactileCatalog,
  DeckTactileEventBinding,
  DeckTactileParamValue,
  DeckTactileSoundRef,
} from './types'

export interface ResolvedTactileEvent {
  eventID: string
  patch?: DeckSoundPatch
  haptic?: DeckTactileEventBinding['haptic']
  params: Record<string, DeckTactileParamValue>
}

function soundRefID(ref: DeckTactileSoundRef): string {
  return typeof ref === 'string' ? ref : ref.ref
}

function soundRefParams(ref: DeckTactileSoundRef): Record<string, DeckTactileParamValue> {
  return typeof ref === 'string' ? {} : (ref.params ?? {})
}

export class DeckTactileTheme {
  private catalog: DeckTactileCatalog

  constructor(catalog: DeckTactileCatalog = catalogJSON as DeckTactileCatalog) {
    this.catalog = catalog
  }

  replaceCatalog(catalog: DeckTactileCatalog) {
    this.catalog = catalog
  }

  merge(overlay: DeckTactileCatalog) {
    this.catalog = {
      ...this.catalog,
      ...overlay,
      sounds: { ...this.catalog.sounds, ...overlay.sounds },
      events: { ...this.catalog.events, ...overlay.events },
    }
  }

  resolve(eventID: string, params: Record<string, DeckTactileParamValue> = {}): ResolvedTactileEvent | null {
    const binding = this.catalog.events[eventID]
    if (!binding) return null

    const mergedParams = { ...params }
    let patch: DeckSoundPatch | undefined
    if (binding.sound && binding.hapticOnly !== true) {
      const ref = binding.sound
      const patchID = soundRefID(ref)
      Object.assign(mergedParams, soundRefParams(ref))
      patch = this.catalog.sounds[patchID]
    }

    return {
      eventID,
      patch,
      haptic: binding.soundOnly === true ? undefined : binding.haptic,
      params: mergedParams,
    }
  }
}

export const defaultDeckTactileTheme = new DeckTactileTheme()
