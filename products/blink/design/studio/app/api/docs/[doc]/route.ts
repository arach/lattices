import { NextRequest, NextResponse } from 'next/server';
import { readFile } from 'fs/promises';
import { join } from 'path';

// Serves the real planning docs from the blink repo's docs/ directory so the
// studio renders the single source of truth instead of copies.

const DOCS: Record<string, string> = {
  'v2-plan': 'v2-plan.md',
  'ui-map': 'v2-ui-map.md',
  'functionality-v1': 'functionality-v1.md',
  'notes-representation': 'notes-representation.md',
  'config': 'config.md',
};

const DOCS_DIR = join(process.cwd(), '..', '..', 'docs');

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ doc: string }> },
) {
  const { doc } = await params;
  const filename = DOCS[doc];
  if (!filename) {
    return NextResponse.json({ ok: false, error: 'unknown doc' }, { status: 404 });
  }

  try {
    const body = await readFile(join(DOCS_DIR, filename), 'utf8');
    return NextResponse.json({ ok: true, doc, body });
  } catch (err) {
    return NextResponse.json({ ok: false, error: String(err) }, { status: 500 });
  }
}
