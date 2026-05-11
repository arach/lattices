export type Frontmatter = Record<string, string | number | boolean | string[] | undefined>

export function splitFrontmatter(raw: string): { data: Frontmatter; content: string } {
  const normalized = raw.replace(/\r\n/g, '\n')
  if (!normalized.startsWith('---\n')) {
    return { data: {}, content: normalized.trim() }
  }

  const end = normalized.indexOf('\n---', 4)
  if (end === -1) {
    return { data: {}, content: normalized.trim() }
  }

  const block = normalized.slice(4, end)
  const content = normalized.slice(end + 4).trim()
  return { data: parseFrontmatterBlock(block), content }
}

function parseFrontmatterBlock(block: string): Frontmatter {
  const data: Frontmatter = {}

  for (const line of block.split('\n')) {
    const match = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/)
    if (!match) continue

    data[match[1]] = parseValue(match[2])
  }

  return data
}

function parseValue(raw: string): string | number | boolean | string[] {
  const value = raw.trim()

  if (value === 'true') return true
  if (value === 'false') return false

  if (/^-?\d+(\.\d+)?$/.test(value)) {
    return Number(value)
  }

  if (value.startsWith('[') && value.endsWith(']')) {
    return value
      .slice(1, -1)
      .split(',')
      .map((part) => stripQuotes(part.trim()))
      .filter(Boolean)
  }

  return stripQuotes(value)
}

function stripQuotes(value: string): string {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1)
  }

  return value
}
