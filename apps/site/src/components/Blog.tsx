import { blogPosts, getBlogPost, type BlogPost } from '../lib/content'
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

  if (!post) {
    return (
      <>
        <PostNav />
        <main className="not-found">
          <h1>Post not found</h1>
          <a href="/blog">Back to blog</a>
        </main>
      </>
    )
  }

  return (
    <>
      <PostNav />
      <article className="post-container" data-pagefind-body>
        <a href="/blog" className="post-back">← all posts</a>
        <h1 className="post-title">{post.title}</h1>
        <div className="post-meta">
          {post.author && <span>{post.author} · </span>}
          {formatDate(post.date)}
          <TagList tags={post.tags} />
        </div>
        <MarkdownRenderer content={post.content} className="prose" />
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
