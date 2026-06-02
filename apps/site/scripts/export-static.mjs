import { copyFile, mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { basename, dirname, join, resolve } from 'node:path'
import { marked } from 'marked'
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript'
import { createHighlighterCore } from 'shiki/core'
import bash from 'shiki/langs/sh.mjs'
import javascript from 'shiki/langs/js.mjs'
import json from 'shiki/langs/json.mjs'
import markdown from 'shiki/langs/md.mjs'
import mermaid from 'shiki/langs/mermaid.mjs'
import swift from 'shiki/langs/swift.mjs'
import typescript from 'shiki/langs/ts.mjs'
import { writeAgentArtifacts } from './agent-docs.mjs'
import { renderMdxComponent } from './render-mdx.mjs'
import { getLastUpdatedBatch, repoInfo } from './git-meta.mjs'

const siteDir = resolve(import.meta.dirname, '..')
const repoRoot = resolve(siteDir, '..', '..')
const distDir = join(siteDir, 'dist')
const SITE_URL = 'https://lattices.dev'
const template = await readFile(join(distDir, 'index.html'), 'utf8')
const shikiTheme = JSON.parse(await readFile(join(siteDir, 'src', 'data', 'lattices-shiki-theme.json'), 'utf8'))
const highlighter = await createHighlighterCore({
  themes: [shikiTheme],
  langs: [
    ...bash,
    ...json,
    ...javascript,
    ...typescript,
    ...swift,
    ...markdown,
    ...mermaid,
  ],
  engine: createJavaScriptRegexEngine(),
})

marked.use({
  mangle: false,
  headerIds: true,
  renderer: createRenderer(),
})

const docs = await readEntries(join(repoRoot, 'docs'), ['.md'])
const posts = (await readEntries(join(siteDir, 'content', 'blog'), ['.md', '.mdx']))
  .filter((post) => !post.data.draft)
  .sort((left, right) => new Date(right.data.date).getTime() - new Date(left.data.date).getTime())

const docUpdated = await getLastUpdatedBatch(
  repoRoot,
  docs.map((doc) => ({ slug: doc.slug, path: join('docs', `${doc.slug}.md`) })),
)
const postUpdated = await getLastUpdatedBatch(
  repoRoot,
  posts.map((post) => ({
    slug: post.slug,
    path: join('apps', 'site', 'content', 'blog', `${post.slug}.mdx`),
  })),
)

await writeRoute('/docs', 'Docs — Lattices', 'Lattices documentation', renderDoc(docs.find((doc) => doc.slug === 'overview') || docs[0]))

for (const doc of docs) {
  await writeRoute(
    `/docs/${doc.slug}`,
    `${doc.data.title || titleFromSlug(doc.slug)} — Lattices Docs`,
    doc.data.description || 'Lattices documentation',
    renderDoc(doc),
  )
}

await writeRoute('/blog', 'Blog — Lattices', 'Ideas and engineering notes from the Lattices team.', renderBlogIndex(posts))
await writeRoute('/docs/blog', 'Blog — Lattices', 'Ideas and engineering notes from the Lattices team.', renderBlogIndex(posts))

for (const post of posts) {
  const html = renderPost(post)
  await writeRoute(`/blog/${post.slug}`, `${post.data.title} — Lattices`, post.data.description || '', html)
  await writeRoute(`/docs/blog/${post.slug}`, `${post.data.title} — Lattices`, post.data.description || '', html)
}

await copyDocsAssets()
await writeAgentArtifacts({ siteDir, repoRoot, distDir })

// Emit a tiny manifest the React SPA can read on hydration for last-updated
// timestamps without shelling out to git at runtime.
await writeFile(
  join(distDir, 'build-meta.json'),
  JSON.stringify(
    {
      generatedAt: new Date().toISOString(),
      repo: { url: repoInfo.repoUrl, branch: repoInfo.branch },
      docs: Object.fromEntries(
        docs.map((doc) => [
          doc.slug,
          {
            updatedAt: docUpdated[doc.slug] || null,
            editUrl: repoInfo.editDocUrl(doc.slug),
          },
        ]),
      ),
      posts: Object.fromEntries(
        posts.map((post) => [
          post.slug,
          {
            updatedAt: postUpdated[post.slug] || null,
            editUrl: repoInfo.editBlogUrl(post.slug),
          },
        ]),
      ),
    },
    null,
    2,
  ),
)

await writeSitemap()
await writeRobots()
await writeRssFeed()
await writeNotFound()

async function writeSitemap() {
  const urls = [
    { loc: `${SITE_URL}/`, priority: '1.0' },
    { loc: `${SITE_URL}/blog`, priority: '0.8' },
    ...docs.map((doc) => ({
      loc: `${SITE_URL}/docs/${doc.slug}`,
      lastmod: docUpdated[doc.slug] || doc.data.date || undefined,
      priority: '0.7',
    })),
    ...posts.map((post) => ({
      loc: `${SITE_URL}/blog/${post.slug}`,
      lastmod: postUpdated[post.slug] || post.data.date || undefined,
      priority: '0.6',
    })),
  ]

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls
  .map(
    (u) =>
      `  <url><loc>${u.loc}</loc>${u.lastmod ? `<lastmod>${u.lastmod}</lastmod>` : ''}<priority>${u.priority}</priority></url>`,
  )
  .join('\n')}
</urlset>
`
  await writeFile(join(distDir, 'sitemap.xml'), xml)
}

async function writeRobots() {
  const body = `User-agent: *
Allow: /

Sitemap: ${SITE_URL}/sitemap.xml
`
  await writeFile(join(distDir, 'robots.txt'), body)
}

async function writeRssFeed() {
  const items = posts
    .map((post) => {
      const link = `${SITE_URL}/blog/${post.slug}`
      const pubDate = new Date(post.data.date).toUTCString()
      return `    <item>
      <title>${escapeXml(post.data.title || titleFromSlug(post.slug))}</title>
      <link>${link}</link>
      <guid>${link}</guid>
      <pubDate>${pubDate}</pubDate>
      ${post.data.author ? `<dc:creator>${escapeXml(post.data.author)}</dc:creator>` : ''}
      <description>${escapeXml(post.data.description || '')}</description>
    </item>`
    })
    .join('\n')

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>lattices — blog</title>
    <link>${SITE_URL}/blog</link>
    <description>Ideas and engineering notes from the Lattices team.</description>
    <language>en-us</language>
${items}
  </channel>
</rss>
`
  await writeFile(join(distDir, 'rss.xml'), xml)
}

function escapeXml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

async function readEntries(directory, extensions) {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = entries
    .filter((entry) => entry.isFile() && extensions.some((extension) => entry.name.endsWith(extension)))
    .map((entry) => entry.name)

  return Promise.all(files.map(async (file) => {
    const raw = await readFile(join(directory, file), 'utf8')
    const parsed = splitFrontmatter(raw)
    return {
      slug: file.replace(/\.(md|mdx)$/, ''),
      ...parsed,
    }
  }))
}

async function writeRoute(route, title, description, appHtml) {
  const html = template
    .replace(/<title>.*?<\/title>/, `<title>${escapeHtml(title)}</title>`)
    .replace(
      /<meta name="description" content=".*?" \/>/,
      `<meta name="description" content="${escapeHtml(description)}" />`,
    )
    .replace(
      /<link rel="canonical" href=".*?" \/>/,
      `<link rel="canonical" href="${SITE_URL}${route}" />`,
    )
    .replace(
      /<link rel="alternate" type="application\/rss\+xml".*?\/>/,
      '',
    )
    .replace(
      '<div id="root"></div>',
      `<div id="root">${appHtml}</div>` +
        (route === '/'
          ? '<link rel="alternate" type="application/rss+xml" title="lattices blog" href="/rss.xml" />'
          : ''),
    )

  const filePath = route === '/' ? join(distDir, 'index.html') : join(distDir, route.slice(1), 'index.html')
  await mkdir(dirname(filePath), { recursive: true })
  await writeFile(filePath, html)
}

async function writeNotFound() {
  const title = 'Page not found — Lattices'
  const description = "We couldn't find that page. Here are some good places to start."
  const body = `
    <main class="not-found-shell" data-pagefind-ignore>
      <div class="not-found-card">
        <p class="not-found-kicker">404</p>
        <h1 class="not-found-title">We couldn't find that page</h1>
        <p class="not-found-desc">The link may be outdated, or we may have moved the page. Try one of these instead:</p>
        <ul class="not-found-suggestions">
          <li><a href="/docs/overview">Documentation overview</a> — what lattices is and how to install it</li>
          <li><a href="/docs/quickstart">Quickstart</a> — running workspaces in 2 minutes</li>
          <li><a href="/docs/api">Agent API</a> — WebSocket reference for agents and scripts</li>
          <li><a href="/blog">Blog</a> — release notes and engineering write-ups</li>
          <li><a href="https://github.com/arach/lattices" target="_blank" rel="noopener noreferrer">GitHub</a> — open an issue if the link should work</li>
        </ul>
      </div>
    </main>
  `
  const html = template
    .replace(/<title>.*?<\/title>/, `<title>${escapeHtml(title)}</title>`)
    .replace(
      /<meta name="description" content=".*?" \/>/,
      `<meta name="description" content="${escapeHtml(description)}" />`,
    )
    .replace('<div id="root"></div>', `<div id="root">${body}</div>`)

  await writeFile(join(distDir, '404.html'), html)
}

function renderDoc(doc) {
  if (!doc) return ''

  const title = doc.data.title || titleFromSlug(doc.slug)
  const description = doc.data.description || ''
  const { content, components } = prepareMarkdown(doc.content)
  const rendered = substituteMdxComponents(marked.parse(content), components)
  const updated = docUpdated[doc.slug]
  return `
    <main class="docs-shell" data-pagefind-body>
      <article class="docs-article">
        <header class="docs-article-header">
          <h1>${escapeHtml(title)}</h1>
          ${description ? `<p>${escapeHtml(description)}</p>` : ''}
          <div class="docs-meta">
            ${updated ? `<span>Updated ${formatDate(updated)}</span>` : ''}
            <a href="${repoInfo.editDocUrl(doc.slug)}" target="_blank" rel="noopener noreferrer">Edit on GitHub →</a>
          </div>
        </header>
        <div class="markdown-body">${rendered}</div>
      </article>
    </main>
  `
}

function renderBlogIndex(items) {
  return `
    <main class="blog-container" data-pagefind-body>
      <h1>Blog</h1>
      ${items.map((post) => `
        <article class="blog-post">
          <a href="/blog/${post.slug}"><h2 class="blog-post-title">${escapeHtml(post.data.title || titleFromSlug(post.slug))}</h2></a>
          <p class="blog-post-meta">${formatDate(post.data.date)}</p>
          <p class="blog-post-desc">${escapeHtml(post.data.description || '')}</p>
        </article>
      `).join('')}
    </main>
  `
}

function renderPost(post) {
  const { content, components } = prepareMarkdown(post.content)
  const rendered = substituteMdxComponents(marked.parse(content), components)
  const updated = postUpdated[post.slug]
  const index = posts.findIndex((p) => p.slug === post.slug)
  const newer = index > 0 ? posts[index - 1] : null // posts are sorted newest first
  const older = index < posts.length - 1 ? posts[index + 1] : null
  return `
    <article class="post-container" data-pagefind-body>
      <a href="/blog" class="post-back">← all posts</a>
      <h1 class="post-title">${escapeHtml(post.data.title || titleFromSlug(post.slug))}</h1>
      <div class="post-meta">
        ${post.data.author ? `${escapeHtml(post.data.author)} · ` : ''}
        ${formatDate(post.data.date)}
        ${updated && updated !== post.data.date ? ` · updated ${formatDate(updated)}` : ''}
        <a href="${repoInfo.editBlogUrl(post.slug)}" target="_blank" rel="noopener noreferrer" class="post-edit-link">Edit on GitHub →</a>
      </div>
      <div class="prose">${rendered}</div>
      <nav class="post-nav-pager" aria-label="More posts">
        ${older ? `<a class="post-pager post-pager-prev" href="/blog/${older.slug}"><span>Newer</span><strong>${escapeHtml(older.data.title || titleFromSlug(older.slug))}</strong></a>` : '<span></span>'}
        ${newer ? `<a class="post-pager post-pager-next" href="/blog/${newer.slug}"><span>Older</span><strong>${escapeHtml(newer.data.title || titleFromSlug(newer.slug))}</strong></a>` : '<span></span>'}
      </nav>
    </article>
  `
}

function substituteMdxComponents(html, components) {
  if (components.length === 0) return html
  return html.replace(/<!--LATTICES-MDX-(\d+)-->/g, (_, index) => {
    const name = components[Number(index)]
    return name ? renderMdxComponent(name) : ''
  })
}

function splitFrontmatter(raw) {
  const normalized = raw.replace(/\r\n/g, '\n')
  if (!normalized.startsWith('---\n')) return { data: {}, content: normalized.trim() }

  const end = normalized.indexOf('\n---', 4)
  if (end === -1) return { data: {}, content: normalized.trim() }

  return {
    data: parseFrontmatter(normalized.slice(4, end)),
    content: normalized.slice(end + 4).trim(),
  }
}

function parseFrontmatter(block) {
  const data = {}
  for (const line of block.split('\n')) {
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/)
    if (!match) continue
    data[match[1]] = parseValue(match[2])
  }
  return data
}

function parseValue(raw) {
  const value = raw.trim()
  if (value === 'true') return true
  if (value === 'false') return false
  if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value)
  if (value.startsWith('[') && value.endsWith(']')) {
    return value.slice(1, -1).split(',').map((part) => stripQuotes(part.trim())).filter(Boolean)
  }
  return stripQuotes(value)
}

function stripQuotes(value) {
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1)
  }
  return value
}

function prepareMarkdown(content) {
  let prepared = content
    .replace(/^import\s+.+$/gm, '')
    .replace(/\sclient:load/g, '')

  // Replace each MDX component tag with a unique HTML comment marker that
  // marked will pass through untouched (plain-text markers like
  // __FOO_0__ get interpreted as markdown emphasis and break). After
  // marked.parse(), the static export substitutes those markers with the
  // rendered static HTML.
  const components = []
  prepared = prepared.replace(/<(StatsRow|LatencyJourney|TurnPipeline|ArchDiagram|ContextExplorer|TestResults)\s*\/>/g, (_, name) => {
    const index = components.length
    components.push(name)
    return `<!--LATTICES-MDX-${index}-->`
  })

  return { content: prepared.trim(), components }
}

async function copyDocsAssets() {
  const assets = ['architecture.svg', 'app-latest.png', 'app-screenshot.png']

  for (const asset of assets) {
    try {
      await mkdir(join(distDir, 'docs'), { recursive: true })
      await copyFile(join(siteDir, 'public', asset), join(distDir, 'docs', asset))
    } catch {
      // Optional compatibility copy for historical /docs/* asset URLs.
    }
  }
}

function titleFromSlug(slug) {
  return basename(slug)
    .split('-')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ')
}

function formatDate(value) {
  return new Date(value).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function createRenderer() {
  const renderer = new marked.Renderer()

  renderer.code = (token) => {
    const language = normalizeLanguage(token.lang)
    const highlighted = highlightStaticCode(token.text, language)

    return [
      '<div class="code-block">',
      '<button type="button" class="code-copy-button" data-pagefind-ignore>Copy</button>',
      `<div class="shiki-code">${highlighted}</div>`,
      '</div>',
    ].join('')
  }

  return renderer
}

function highlightStaticCode(code, language) {
  try {
    return highlighter.codeToHtml(code, { lang: language, theme: 'lattices-green' })
  } catch {
    return highlighter.codeToHtml(code, { lang: 'text', theme: 'lattices-green' })
  }
}

function normalizeLanguage(language) {
  const lang = language?.toLowerCase().trim()

  if (!lang) return 'text'
  if (lang === 'sh' || lang === 'shell' || lang === 'zsh') return 'bash'
  if (lang === 'js' || lang === 'jsx') return 'javascript'
  if (lang === 'ts' || lang === 'tsx') return 'typescript'

  return ['bash', 'json', 'javascript', 'typescript', 'swift', 'markdown', 'mermaid', 'text'].includes(lang)
    ? lang
    : 'text'
}
