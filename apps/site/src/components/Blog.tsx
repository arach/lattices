import { useEffect, useState } from 'react'
import { blogPosts, getBlogPost, type BlogPost } from '../lib/content'
import { formatBuildDate, getBuildMeta, type PostMeta } from '../lib/build-meta'
import { MarkdownRenderer } from './MarkdownRenderer'
import { LatticesMark } from './SiteChrome'

export function BlogIndex() {
  return (
    <>
      <PostNav />
      <main className="blog-container" data-pagefind-body>
        <h1>Blog</h1>
        {blogPosts.map((post) => (
          <article className="blog-post" key={post.slug}>
            <a href={`/blog/${post.slug}`}>
              <h2 className="blog-post-title">{post.title}</h2>
            </a>
            <p className="blog-post-meta">{formatDate(post.date)}</p>
            <p className="blog-post-desc">{post.description}</p>
            <TagList tags={post.tags} />
          </article>
        ))}
      </main>
    </>
  )
}

export function BlogPostPage({ slug }: { slug: string }) {
  const post = getBlogPost(slug)
  const [meta, setMeta] = useState<PostMeta | null>(null)

  useEffect(() => {
    if (!post) return
    let cancelled = false
    getBuildMeta().then((m) => {
      if (cancelled) return
      setMeta(m?.posts?.[post.slug] ?? null)
    })
    return () => {
      cancelled = true
    }
  }, [post])

  if (!post) {
    return (
      <>
        <PostNav />
        <main className="not-found-shell" data-pagefind-ignore>
          <div className="not-found-card">
            <p className="not-found-kicker">404</p>
            <h1 className="not-found-title">Post not found</h1>
            <p className="not-found-desc">
              The post may have been moved or unpublished.{' '}
              <a href="/blog">Browse the blog →</a>
            </p>
          </div>
        </main>
      </>
    )
  }

  const index = blogPosts.findIndex((p) => p.slug === post.slug)
  const newer = index > 0 ? blogPosts[index - 1] : null // blogPosts sorted newest first
  const older = index >= 0 && index < blogPosts.length - 1 ? blogPosts[index + 1] : null
  const updatedLabel = formatBuildDate(meta?.updatedAt)
  const showUpdated = updatedLabel && updatedLabel !== formatDate(post.date)

  return (
    <>
      <PostNav />
      <article className="post-container" data-pagefind-body>
        <a href="/blog" className="post-back">← all posts</a>
        <h1 className="post-title">{post.title}</h1>
        <div className="post-meta">
          {post.author && <span>{post.author} · </span>}
          {formatDate(post.date)}
          {showUpdated && <span> · updated {updatedLabel}</span>}
          {meta?.editUrl && (
            <a
              href={meta.editUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="post-edit-link"
            >
              Edit on GitHub →
            </a>
          )}
          <TagList tags={post.tags} />
        </div>
        <MarkdownRenderer content={post.content} className="prose" />
        <nav className="post-nav-pager" aria-label="More posts">
          {older ? (
            <a className="post-pager post-pager-prev" href={`/blog/${older.slug}`}>
              <span className="post-pager-label">Newer</span>
              <strong>{older.title}</strong>
            </a>
          ) : (
            <span />
          )}
          {newer ? (
            <a className="post-pager post-pager-next" href={`/blog/${newer.slug}`}>
              <span className="post-pager-label">Older</span>
              <strong>{newer.title}</strong>
            </a>
          ) : (
            <span />
          )}
        </nav>
      </article>
    </>
  )
}

function PostNav() {
  return (
    <nav className="post-nav" data-pagefind-ignore>
      <div className="post-nav-inner">
        <a href="/" className="post-nav-brand">
          <LatticesMark />
          <span>lattices</span>
        </a>
        <div className="post-nav-links">
          <a href="/blog">Blog</a>
          <a href="/docs/overview">Docs</a>
        </div>
      </div>
    </nav>
  )
}

function TagList({ tags }: { tags: BlogPost['tags'] }) {
  if (tags.length === 0) return null

  return (
    <div className="post-tags">
      {tags.map((tag) => (
        <span className="post-tag" key={tag}>{tag}</span>
      ))}
    </div>
  )
}

function formatDate(value: string): string {
  return new Date(value).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
}
