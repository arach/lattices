import { useCallback, useMemo, useRef } from 'react'
import catalogJSON from './catalog.json'
import { playPatch } from './synthesizer'
import { DeckTactileTheme } from './theme'
import type { DeckTactileCatalog, DeckTactileEventID, DeckTactileParamValue } from './types'

export function useDeckTactile(enabled: boolean, catalog?: DeckTactileCatalog) {
  const theme = useMemo(() => new DeckTactileTheme(catalog ?? (catalogJSON as DeckTactileCatalog)), [catalog])
  const audioCtxRef = useRef<AudioContext | null>(null)

  const getAudioContext = useCallback((): AudioContext | null => {
    if (!enabled) return null
    try {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
      if (!audioCtxRef.current) audioCtxRef.current = new AudioCtx()
      const ctx = audioCtxRef.current
      if (ctx.state === 'suspended') void ctx.resume()
      return ctx
    } catch {
      return null
    }
  }, [enabled])

  const play = useCallback(
    (eventID: DeckTactileEventID | string, params: Record<string, DeckTactileParamValue> = {}) => {
      const ctx = getAudioContext()
      if (!ctx) return
      const resolved = theme.resolve(eventID, params)
      if (!resolved?.patch) return
      playPatch(ctx, resolved.patch, resolved.params)
    },
    [getAudioContext, theme]
  )

  return { play, theme }
}
