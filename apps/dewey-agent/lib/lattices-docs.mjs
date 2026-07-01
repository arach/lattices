import { access, readFile, stat } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const appRoot = resolve(here, '..')
const repoFromApp = resolve(appRoot, '..', '..')

const requiredSourceFiles = [
  'AGENTS.md',
  'llms.txt',
  'docs/agents.md',
  'docs/api.md',
  'docs/config.md',
  'docs/agent/cua-implementation.md',
  'apps/site/scripts/agent-docs.mjs',
]

const requiredDistArtifacts = [
  'AGENTS.md',
  'llms.txt',
  'docs.json',
  'agent-docs.json',
  'agent/context.md',
  'agent/manifest.json',
  'agent/docs.json',
  'agent/raw/docs/agents.md',
  'agent/bundles/core.md',
]

export function resolveRepoRoot(input = {}) {
  return resolve(input.repoRoot || process.env.LATTICES_REPO || repoFromApp)
}

export function resolveSiteDir(repoRoot) {
  return join(repoRoot, 'apps/site')
}

export function resolveDistDir(repoRoot) {
  return join(resolveSiteDir(repoRoot), 'dist')
}

async function pathExists(filePath) {
  try {
    await access(filePath)
    return true
  } catch {
    return false
  }
}

async function fileSize(filePath) {
  try {
    const info = await stat(filePath)
    return info.size
  } catch {
    return 0
  }
}

async function loadAgentDocsModule(repoRoot) {
  const modulePath = join(repoRoot, 'apps/site/scripts/agent-docs.mjs')
  if (!(await pathExists(modulePath))) {
    throw new Error(`Missing agent docs script at ${modulePath}`)
  }
  return import(pathToFileURL(modulePath).href)
}

export async function collectDocs(input = {}) {
  const repoRoot = resolveRepoRoot(input)
  const siteDir = resolveSiteDir(repoRoot)
  const distDir = input.distDir ? resolve(input.distDir) : resolveDistDir(repoRoot)
  const docsDir = join(repoRoot, 'docs')
  const agentDocs = await loadAgentDocsModule(repoRoot)
  const docs = await agentDocs.readMarkdownDocs({ repoRoot, siteDir, docsDir, distDir })
  const manifest = await agentDocs.buildAgentManifest({ repoRoot, siteDir, docsDir, distDir, docs })
  const prompts = docs.filter((doc) => doc.kind === 'prompt')

  return {
    repoRoot,
    siteDir,
    docsDir,
    distDir,
    docsCount: docs.length,
    promptCount: prompts.length,
    recommendedReadOrder: manifest.recommendedReadOrder,
    artifacts: manifest.artifacts,
    docs: docs.map((doc) => ({
      slug: doc.slug,
      kind: doc.kind,
      title: doc.title,
      sourcePath: doc.sourcePath,
      tokensEstimate: doc.tokensEstimate,
      headings: doc.headings.map((heading) => heading.text),
    })),
  }
}

export async function generateAgentArtifacts(input = {}) {
  const repoRoot = resolveRepoRoot(input)
  const siteDir = resolveSiteDir(repoRoot)
  const distDir = input.distDir ? resolve(input.distDir) : resolveDistDir(repoRoot)
  const docsDir = join(repoRoot, 'docs')
  const agentDocs = await loadAgentDocsModule(repoRoot)
  const result = await agentDocs.writeAgentArtifacts({ repoRoot, siteDir, docsDir, distDir })

  return {
    repoRoot,
    distDir,
    ...result,
  }
}

export async function auditAgentDocs(input = {}) {
  const repoRoot = resolveRepoRoot(input)
  const distDir = input.distDir ? resolve(input.distDir) : resolveDistDir(repoRoot)
  const collected = await collectDocs({ repoRoot, distDir })

  const sources = await Promise.all(requiredSourceFiles.map(async (relativePath) => ({
    path: relativePath,
    exists: await pathExists(join(repoRoot, relativePath)),
    size: await fileSize(join(repoRoot, relativePath)),
  })))

  const artifacts = await Promise.all(requiredDistArtifacts.map(async (relativePath) => ({
    path: relativePath,
    exists: await pathExists(join(distDir, relativePath)),
    size: await fileSize(join(distDir, relativePath)),
  })))

  const missingSources = sources.filter((entry) => !entry.exists).map((entry) => entry.path)
  const missingArtifacts = artifacts.filter((entry) => !entry.exists).map((entry) => entry.path)
  const sourceScore = requiredSourceFiles.length - missingSources.length
  const artifactScore = requiredDistArtifacts.length - missingArtifacts.length
  const score = Math.round(((sourceScore + artifactScore) / (requiredSourceFiles.length + requiredDistArtifacts.length)) * 100)

  return {
    repoRoot,
    distDir,
    score,
    docsCount: collected.docsCount,
    promptCount: collected.promptCount,
    missingSources,
    missingArtifacts,
    sources,
    artifacts,
    recommendedReadOrder: collected.recommendedReadOrder,
  }
}

export async function readDocArtifact(input = {}) {
  const repoRoot = resolveRepoRoot(input)
  const slug = String(input.slug || '').replace(/^\/+/, '').replace(/\.mdx?$/, '')
  if (!slug || slug.includes('..')) {
    throw new Error('Provide a safe docs slug, for example "agents" or "agent/cua-implementation".')
  }

  const docsDir = join(repoRoot, 'docs')
  const candidates = [
    join(docsDir, `${slug}.md`),
    join(docsDir, `${slug}.mdx`),
  ]

  for (const candidate of candidates) {
    if (await pathExists(candidate)) {
      return {
        repoRoot,
        slug,
        sourcePath: candidate.slice(repoRoot.length + 1),
        markdown: await readFile(candidate, 'utf8'),
      }
    }
  }

  throw new Error(`No doc found for slug "${slug}" under ${docsDir}`)
}
