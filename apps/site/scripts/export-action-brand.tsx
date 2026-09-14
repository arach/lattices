import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import sharp from 'sharp';
import { mkdir, writeFile } from 'node:fs/promises';
import { ActionMark } from '../src/components/ActionMark';
const out = new URL('../public/brand/action/', import.meta.url);
await mkdir(out, { recursive: true });
for (const theme of ['light', 'dark'] as const) {
 const svg = renderToStaticMarkup(createElement(ActionMark, { theme, guides: false, background: false, viewBox: '15 35 590 590', width: 512, height: 512 }));
 await writeFile(new URL(`action-${theme}.svg`,out), svg);
 for (const size of [16,24,32,48,64,80,128,256,512,1024]) {
  await sharp(Buffer.from(svg)).resize(size,size).png().toFile(new URL(`action-${theme}-${size}.png`,out).pathname);
 }
}
