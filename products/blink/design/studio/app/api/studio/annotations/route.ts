import { NextRequest, NextResponse } from 'next/server';
import { writeFile, readFile, mkdir } from 'fs/promises';
import { join } from 'path';

// Real local persistence for annotations. Writes sidecar JSON files so local
// agents (Cursor, scout, terminal Claude, etc.) can read design feedback from
// the workspace at any time.
//
// Convention: .studio/annotations/<sanitized-key>.json

const STUDIO_DIR = join(process.cwd(), '.studio');
const ANNOTATIONS_DIR = join(STUDIO_DIR, 'annotations');

async function ensureDir() {
  await mkdir(ANNOTATIONS_DIR, { recursive: true });
}

function sanitizeKey(key: string): string {
  return key.replace(/[^a-zA-Z0-9-_]/g, '-').replace(/-+/g, '-').toLowerCase();
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { persistKey, slug, annotations, decisions } = body;

    const key = sanitizeKey(persistKey || slug || 'unknown');
    const payload = {
      updatedAt: new Date().toISOString(),
      slug,
      persistKey: key,
      annotations: annotations ?? [],
      decisions: decisions ?? [],
    };

    await ensureDir();
    const filePath = join(ANNOTATIONS_DIR, `${key}.json`);
    await writeFile(filePath, JSON.stringify(payload, null, 2), 'utf8');

    return NextResponse.json({ ok: true, key, filePath, written: payload });
  } catch (err) {
    console.error('[blink-studio/api] persist error', err);
    return NextResponse.json({ ok: false, error: String(err) }, { status: 500 });
  }
}

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const rawKey = searchParams.get('key') || searchParams.get('slug');
  if (!rawKey) {
    return NextResponse.json({ ok: false, error: 'key or slug required' }, { status: 400 });
  }

  const key = sanitizeKey(rawKey);
  const filePath = join(ANNOTATIONS_DIR, `${key}.json`);

  try {
    const content = await readFile(filePath, 'utf8');
    const data = JSON.parse(content);
    return NextResponse.json({ ok: true, key, filePath, data });
  } catch {
    return NextResponse.json({ ok: true, key, filePath, data: null });
  }
}
