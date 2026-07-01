import { useEffect, useRef, useState } from 'react'

declare global {
  interface Window {
    PagefindUI?: new (options: { element: string; showSubResults?: boolean }) => unknown
  }
}

export function LatticesMark({ size = 20 }: { size?: number }) {
  const cells = [true, false, false, true, false, false, true, true, true]
  const pad = 2
  const gap = 1.2
  const cell = (size - 2 * pad - 2 * gap) / 3

  return (
    <svg
      className="site-mark"
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      fill="none"
      aria-hidden="true"
    >
      {cells.map((bright, index) => {
        const row = Math.floor(index / 3)
        const col = index % 3
        return (
          <rect
            key={index}
            x={pad + col * (cell + gap)}
            y={pad + row * (cell + gap)}
            width={cell}
            height={cell}
            rx={1}
            className="site-mark-cell"
            style={{ fill: bright ? 'var(--logo-ink)' : 'var(--logo-dim)' }}
          />
        )
      })}
    </svg>
  )
}

export function SiteHeader() {
  const [searchOpen, setSearchOpen] = useState(false)
  // The initial theme is set synchronously by the inline script in index.html
  // to avoid a flash of wrong-theme content. This effect re-syncs on toggle.
  const [theme, setTheme] = useState<'light' | 'dark'>(
    () => (document.documentElement.getAttribute('data-theme') as 'light' | 'dark') || 'dark',
  )

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    localStorage.setItem('theme', theme)
  }, [theme])

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const key = event.key.toLowerCase()
      if ((event.metaKey || event.ctrlKey) && key === 'k') {
        event.preventDefault()
        setSearchOpen(true)
      }
    }

    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  return (
    <>
      <header className="site-header" data-pagefind-ignore>
        <div className="site-header-inner">
          <a className="site-brand" href="/">
            <LatticesMark />
            <span>lattices</span>
          </a>
          <nav className="site-links" aria-label="Primary navigation">
            <a href="/blog">Blog</a>
            <a href="/docs/overview">Docs</a>
            <a href="/docs/api">API</a>
            <button type="button" onClick={() => setSearchOpen(true)} aria-label="Open search (Cmd+K)">
              Search
              <span aria-hidden="true">⌘K</span>
            </button>
            <button
              type="button"
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`}
            >
              Theme
            </button>
          </nav>
        </div>
      </header>
      <SearchModal open={searchOpen} onClose={() => setSearchOpen(false)} />
    </>
  )
}

function SearchModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [failed, setFailed] = useState(false)
  const [initError, setInitError] = useState<string | null>(null)
  const initialized = useRef(false)
  const panelRef = useRef<HTMLDivElement>(null)
  const previousFocus = useRef<HTMLElement | null>(null)

  useEffect(() => {
    if (!open || initialized.current) return
    initialized.current = true

    const css = document.createElement('link')
    css.rel = 'stylesheet'
    css.href = '/pagefind/pagefind-ui.css'
    document.head.appendChild(css)

    const script = document.createElement('script')
    script.src = '/pagefind/pagefind-ui.js'
    script.async = true
    script.onload = () => {
      if (window.PagefindUI) {
        try {
          new window.PagefindUI({ element: '#search-modal', showSubResults: true })
        } catch (error) {
          setInitError(error instanceof Error ? error.message : 'unknown')
          setFailed(true)
        }
      } else {
        setFailed(true)
      }
    }
    script.onerror = () => setFailed(true)
    document.head.appendChild(script)
  }, [open])

  // Focus trap + restore previous focus + Escape to close.
  useEffect(() => {
    if (!open) return

    previousFocus.current = document.activeElement as HTMLElement | null

    const focusPanel = () => {
      const panel = panelRef.current
      if (!panel) return
      const focusable = panel.querySelectorAll<HTMLElement>(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
      )
      if (focusable.length > 0) {
        focusable[0].focus()
      } else {
        panel.setAttribute('tabindex', '-1')
        panel.focus()
      }
    }

    const frame = requestAnimationFrame(focusPanel)

    const handleKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault()
        onClose()
        return
      }

      if (event.key !== 'Tab') return
      const panel = panelRef.current
      if (!panel) return
      const focusable = Array.from(
        panel.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
        ),
      ).filter((el) => !el.hasAttribute('disabled'))
      if (focusable.length === 0) {
        event.preventDefault()
        return
      }
      const first = focusable[0]
      const last = focusable[focusable.length - 1]
      const active = document.activeElement as HTMLElement | null
      if (event.shiftKey && active === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && active === last) {
        event.preventDefault()
        first.focus()
      }
    }

    document.addEventListener('keydown', handleKey)
    return () => {
      cancelAnimationFrame(frame)
      document.removeEventListener('keydown', handleKey)
      previousFocus.current?.focus?.()
    }
  }, [open, onClose])

  if (!open) return null

  return (
    <div
      className="search-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Search documentation"
      onClick={(event) => event.target === event.currentTarget && onClose()}
    >
      <div className="search-panel" ref={panelRef}>
        <div className="search-panel-header">
          <div>
            <p>Search</p>
            <h2>Find docs fast</h2>
          </div>
          <button type="button" onClick={onClose} aria-label="Close search">Close</button>
        </div>
        <div id="search-modal" className="search-box" />
        {failed && (
          <p className="search-fallback">
            Search index is generated during build.
            {initError
              ? ` Pagefind error: ${initError}.`
              : ' Run `bun run build` to enable it locally.'}
          </p>
        )}
      </div>
    </div>
  )
}
