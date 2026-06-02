import { useEffect, useState } from 'react'
import { defaultDoc, getDoc, navGroups, type DocPage } from '../lib/content'
import { formatBuildDate, getBuildMeta, type DocMeta } from '../lib/build-meta'
import { MarkdownRenderer } from './MarkdownRenderer'
import { SiteHeader } from './SiteChrome'

interface DocsPageProps {
  slug?: string
}

export function DocsPage({ slug }: DocsPageProps) {
  const doc = slug ? getDoc(slug) : defaultDoc()
  const [meta, setMeta] = useState<DocMeta | null>(null)

  useEffect(() => {
    if (!doc) return
    let cancelled = false
    getBuildMeta().then((m) => {
      if (cancelled) return
      setMeta(m?.docs?.[doc.slug] ?? null)
    })
    return () => {
      cancelled = true
    }
  }, [doc])

  if (!doc) {
    return (
      <>
        <SiteHeader />
        <main className="not-found-shell" data-pagefind-ignore>
          <div className="not-found-card">
            <p className="not-found-kicker">404</p>
            <h1 className="not-found-title">Page not found</h1>
            <p className="not-found-desc">
              The docs page may have been moved.{' '}
              <a href="/docs/overview">Back to the docs overview →</a>
            </p>
          </div>
        </main>
      </>
    )
  }

  const updatedLabel = formatBuildDate(meta?.updatedAt)

  return (
    <>
      <SiteHeader />
      <main className="docs-shell" data-pagefind-body>
        <aside className="docs-sidebar" data-pagefind-ignore>
          <Sidebar key={doc.slug} currentSlug={doc.slug} />
        </aside>
        <article className="docs-article">
          <header className="docs-article-header">
            <h1>{doc.title}</h1>
            {doc.description && <p>{doc.description}</p>}
            <div className="docs-meta">
              {updatedLabel && <span>Updated {updatedLabel}</span>}
              {meta?.editUrl && (
                <a
                  href={meta.editUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Edit on GitHub →
                </a>
              )}
            </div>
          </header>
          <MarkdownRenderer content={doc.content} />
        </article>
        <aside className="docs-toc" data-pagefind-ignore>
          <TableOfContents doc={doc} />
        </aside>
      </main>
    </>
  )
}

function Sidebar({ currentSlug }: { currentSlug: string }) {
  const [mobileOpen, setMobileOpen] = useState(false)
  const currentItem = navGroups.flatMap((group) => group.items).find((item) => item.id === currentSlug)

  return (
    <nav className="sidebar-nav" aria-label="Documentation">
      <div className="desktop-sidebar-nav">
        <NavGroups currentSlug={currentSlug} />
      </div>
      <div className={mobileOpen ? 'mobile-docs-nav open' : 'mobile-docs-nav'}>
        <button
          type="button"
          className="mobile-docs-trigger"
          aria-expanded={mobileOpen}
          aria-controls="mobile-docs-panel"
          onClick={() => setMobileOpen((open) => !open)}
        >
          <span>
            <span className="mobile-docs-label">Docs menu</span>
            <span className="mobile-docs-current">{currentItem?.title || 'Documentation'}</span>
          </span>
          <span className="mobile-docs-chevron" aria-hidden="true">{mobileOpen ? '−' : '+'}</span>
        </button>
        <div id="mobile-docs-panel" className="mobile-docs-panel" hidden={!mobileOpen}>
          <NavGroups currentSlug={currentSlug} compact />
        </div>
      </div>
    </nav>
  )
}

function NavGroups({ currentSlug, compact = false }: { currentSlug: string; compact?: boolean }) {
  return (
    <>
      {navGroups.map((group) => (
        <details key={group.id} open={!compact || group.items.some((item) => item.id === currentSlug)}>
          <summary>
            <span>{group.title}</span>
            <span>▾</span>
          </summary>
          <ul>
            {group.items.map((item) => (
              <li key={item.id}>
                <a className={currentSlug === item.id ? 'active' : undefined} href={item.href}>
                  {item.title}
                </a>
              </li>
            ))}
          </ul>
        </details>
      ))}
    </>
  )
}

function TableOfContents({ doc }: { doc: DocPage }) {
  const headings = doc.headings.filter((heading) => heading.depth >= 2 && heading.depth <= 3)

  if (headings.length === 0) return null

  return (
    <nav className="toc-nav" aria-label="On this page">
      <p>On this page</p>
      <ul>
        {headings.map((heading) => (
          <li key={heading.id} className={heading.depth === 3 ? 'nested' : undefined}>
            <a href={`#${heading.id}`}>{heading.text}</a>
          </li>
        ))}
      </ul>
    </nav>
  )
}
