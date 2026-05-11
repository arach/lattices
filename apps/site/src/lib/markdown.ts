export interface Heading {
  depth: number
  id: string
  text: string
}

const MDX_COMPONENTS = [
  'StatsRow',
  'LatencyJourney',
  'TurnPipeline',
  'ArchDiagram',
  'ContextExplorer',
  'TestResults',
] as const

export function prepareMarkdown(content: string): string {
  let prepared = content
    .replace(/^import\s+.+$/gm, '')
    .replace(/\sclient:load/g, '')

  for (const name of MDX_COMPONENTS) {
    prepared = prepared.replace(
      new RegExp(`<${name}\\s*/>`, 'g'),
      `<div data-mdx-component="${name}"></div>`,
    )
  }

  return prepared.trim()
}

export function extractHeadings(content: string): Heading[] {
  return content
    .split('\n')
    .map((line) => line.match(/^(#{2,3})\s+(.+)$/))
    .filter((match): match is RegExpMatchArray => Boolean(match))
    .map((match) => {
      const text = stripMarkdown(match[2])
      return {
        depth: match[1].length,
        id: slugify(text),
        text,
      }
    })
}

export function slugify(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[`*_~[\]()]/g, '')
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

function stripMarkdown(value: string): string {
  return value
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[*_~]/g, '')
    .trim()
}
