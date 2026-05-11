import shikiTheme from '../data/lattices-shiki-theme.json'
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript'
import { createHighlighterCore } from 'shiki/core'
import bash from 'shiki/langs/sh.mjs'
import javascript from 'shiki/langs/js.mjs'
import json from 'shiki/langs/json.mjs'
import markdown from 'shiki/langs/md.mjs'
import mermaid from 'shiki/langs/mermaid.mjs'
import swift from 'shiki/langs/swift.mjs'
import typescript from 'shiki/langs/ts.mjs'
import type { ThemeRegistrationRaw } from 'shiki/core'

const themeName = 'lattices-green'
const languages = ['bash', 'json', 'javascript', 'typescript', 'swift', 'markdown', 'mermaid', 'text'] as const
const shikiLanguages = [
  ...bash,
  ...json,
  ...javascript,
  ...typescript,
  ...swift,
  ...markdown,
  ...mermaid,
]

type Highlighter = {
  codeToHtml: (code: string, options: { lang: string; theme: string }) => string
}

let highlighterPromise: Promise<Highlighter> | null = null

export async function highlightCode(code: string, language?: string): Promise<string> {
  const highlighter = await getHighlighter()
  const normalized = normalizeLanguage(language)

  try {
    return highlighter.codeToHtml(code, { lang: normalized, theme: themeName })
  } catch {
    return highlighter.codeToHtml(code, { lang: 'text', theme: themeName })
  }
}

export function normalizeLanguage(language?: string): string {
  const lang = language?.toLowerCase().trim()

  if (!lang) return 'text'
  if (lang === 'sh' || lang === 'shell' || lang === 'zsh') return 'bash'
  if (lang === 'js' || lang === 'jsx') return 'javascript'
  if (lang === 'ts' || lang === 'tsx') return 'typescript'
  if (languages.includes(lang as (typeof languages)[number])) return lang

  return 'text'
}

async function getHighlighter(): Promise<Highlighter> {
  highlighterPromise ??= createHighlighterCore({
    themes: [shikiTheme as unknown as ThemeRegistrationRaw],
    langs: shikiLanguages,
    engine: createJavaScriptRegexEngine(),
  }) as Promise<Highlighter>

  return highlighterPromise
}
