import { useEffect } from 'react'
import { BlogIndex, BlogPostPage } from './components/Blog'
import { DocsPage } from './components/Docs'
import LandingPage from './components/LandingPage'
import { defaultDoc, getBlogPost, getDoc } from './lib/content'

export default function SiteApp() {
  const path = normalizePath(window.location.pathname)
  const route = resolveRoute(path)

  useEffect(() => {
    document.title = route.title
    setMeta('description', route.description)
  }, [route.description, route.title])

  if (route.kind === 'home') return <LandingPage />
  if (route.kind === 'docs') return <DocsPage slug={route.slug} />
  if (route.kind === 'blog-index') return <BlogIndex />
  if (route.kind === 'blog-post') return <BlogPostPage slug={route.slug} />

  return (
    <main className="not-found">
      <h1>Page not found</h1>
      <a href="/">Back home</a>
    </main>
  )
}

type Route =
  | { kind: 'home'; title: string; description: string }
  | { kind: 'docs'; slug?: string; title: string; description: string }
  | { kind: 'blog-index'; title: string; description: string }
  | { kind: 'blog-post'; slug: string; title: string; description: string }
  | { kind: 'not-found'; title: string; description: string }

function resolveRoute(path: string): Route {
  if (path === '/') {
    return {
      kind: 'home',
      title: 'lattices — the agentic workspace manager',
      description: 'Turn your Mac workspace into a coherent, agent-accessible API, plus an assistant for windows, tmux sessions, screen text, and layout recovery.',
    }
  }

  if (path === '/blog' || path === '/docs/blog') {
    return {
      kind: 'blog-index',
      title: 'Blog — Lattices',
      description: 'Ideas and engineering notes from the Lattices team.',
    }
  }

  if (path.startsWith('/blog/') || path.startsWith('/docs/blog/')) {
    const slug = path.replace(/^\/(docs\/)?blog\//, '')
    const post = getBlogPost(slug)
    return post
      ? {
          kind: 'blog-post',
          slug,
          title: `${post.title} — Lattices`,
          description: post.description,
        }
      : { kind: 'not-found', title: 'Post not found — Lattices', description: 'Post not found' }
  }

  if (path === '/docs') {
    const doc = defaultDoc()
    return {
      kind: 'docs',
      slug: doc.slug,
      title: `${doc.title} — Lattices Docs`,
      description: doc.description || 'Lattices documentation',
    }
  }

  if (path.startsWith('/docs/')) {
    const slug = path.replace(/^\/docs\//, '')
    const doc = getDoc(slug)
    return doc
      ? {
          kind: 'docs',
          slug,
          title: `${doc.title} — Lattices Docs`,
          description: doc.description || 'Lattices documentation',
        }
      : { kind: 'not-found', title: 'Page not found — Lattices', description: 'Page not found' }
  }

  return {
    kind: 'not-found',
    title: 'Page not found — Lattices',
    description: 'Page not found',
  }
}

function normalizePath(pathname: string): string {
  if (pathname.length > 1 && pathname.endsWith('/')) {
    return pathname.slice(0, -1)
  }

  return pathname
}

function setMeta(name: string, content: string): void {
  const meta = document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`)
  if (meta) {
    meta.content = content
  }
}
