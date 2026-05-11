import { defaultDoc, getDoc, navGroups, type DocPage } from '../lib/content'
import { MarkdownRenderer } from './MarkdownRenderer'
import { SiteHeader } from './SiteChrome'

interface DocsPageProps {
  slug?: string
}

export function DocsPage({ slug }: DocsPageProps) {
  const doc = slug ? getDoc(slug) : defaultDoc()

  if (!doc) {
    return (
      <>
        <SiteHeader />
        <main className="not-found">
          <h1>Page not found</h1>
          <a href="/docs/overview">Back to docs</a>
        </main>
      </>
    )
  }

  return (
    <>
      <SiteHeader />
      <main className="docs-shell" data-pagefind-body>
        <aside className="docs-sidebar" data-pagefind-ignore>
          <Sidebar currentSlug={doc.slug} />
        </aside>
        <article className="docs-article">
          <header className="docs-article-header">
            <h1>{doc.title}</h1>
            {doc.description && <p>{doc.description}</p>}
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
  return (
    <nav className="sidebar-nav" aria-label="Documentation">
      {navGroups.map((group) => (
        <details key={group.id} open>
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
    </nav>
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
