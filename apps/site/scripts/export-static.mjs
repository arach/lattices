import { copyFile, mkdir, readdir, readFile, writeFile } from 'node:fs/promises'
import { basename, dirname, join, resolve } from 'node:path'
import { marked } from 'marked'
import { writeAgentArtifacts } from './agent-docs.mjs'

const siteDir = resolve(import.meta.dirname, '..')
const repoRoot = resolve(siteDir, '..', '..')
const distDir = join(siteDir, 'dist')
const template = await readFile(join(distDir, 'index.html'), 'utf8')

marked.use({
  mangle: false,
  headerIds: true,
})

const mdxComponents = [
  'StatsRow',
  'LatencyJourney',
  'TurnPipeline',
  'ArchDiagram',
  'ContextExplorer',
  'TestResults',
]

const docs = await readEntries(join(repoRoot, 'docs'), ['.md'])
const posts = (await readEntries(join(siteDir, 'content', 'blog'), ['.md', '.mdx']))
  .filter((post) => !post.data.draft)
  .sort((left, right) => new Date(right.data.date).getTime() - new Date(left.data.date).getTime())

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
    .replace('<div id="root"></div>', `<div id="root">${appHtml}</div>`)

  const filePath = route === '/' ? join(distDir, 'index.html') : join(distDir, route.slice(1), 'index.html')
  await mkdir(dirname(filePath), { recursive: true })
  await writeFile(filePath, html)
}

function renderDoc(doc) {
  if (!doc) return ''

  const title = doc.data.title || titleFromSlug(doc.slug)
  const description = doc.data.description || ''
  return `
    <main class="docs-shell" data-pagefind-body>
      <article class="docs-article">
        <header class="docs-article-header">
          <h1>${escapeHtml(title)}</h1>
          ${description ? `<p>${escapeHtml(description)}</p>` : ''}
        </header>
        <div class="markdown-body">${marked.parse(prepareMarkdown(doc.content))}</div>
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
  return `
    <article class="post-container" data-pagefind-body>
      <a href="/blog" class="post-back">← all posts</a>
      <h1 class="post-title">${escapeHtml(post.data.title || titleFromSlug(post.slug))}</h1>
      <div class="post-meta">
        ${post.data.author ? `${escapeHtml(post.data.author)} · ` : ''}
        ${formatDate(post.data.date)}
      </div>
      <div class="prose">${marked.parse(prepareMarkdown(post.content))}</div>
    </article>
  `
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

  for (const name of mdxComponents) {
    prepared = prepared.replace(new RegExp(`<${name}\\s*/>`, 'g'), '')
  }

  return prepared.trim()
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
