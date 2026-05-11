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
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} fill="none" aria-hidden="true">
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
            fill={bright ? '#f2f2f2' : 'rgba(255,255,255,0.18)'}
          />
        )
      })}
    </svg>
  )
}

export function SiteHeader() {
  const [searchOpen, setSearchOpen] = useState(false)
  const [theme, setTheme] = useState(() => localStorage.getItem('theme') || 'dark')

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
            <button type="button" onClick={() => setSearchOpen(true)}>
              Search
              <span>⌘K</span>
            </button>
            <button type="button" onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}>
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
  const initialized = useRef(false)

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
        new window.PagefindUI({ element: '#search-modal', showSubResults: true })
      } else {
        setFailed(true)
      }
    }
    script.onerror = () => setFailed(true)
    document.head.appendChild(script)
  }, [open])

  if (!open) return null

  return (
    <div className="search-overlay" onClick={(event) => event.target === event.currentTarget && onClose()}>
      <div className="search-panel">
        <div className="search-panel-header">
          <div>
            <p>Search</p>
            <h2>Find docs fast</h2>
          </div>
          <button type="button" onClick={onClose}>Close</button>
        </div>
        <div id="search-modal" className="search-box" />
        {failed && (
          <p className="search-fallback">
            Search index is generated during build. Run <code>bun run build</code> to enable it locally.
          </p>
        )}
      </div>
    </div>
  )
}
