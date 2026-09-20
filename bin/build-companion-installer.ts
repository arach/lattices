import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { mkdirSync } from 'node:fs';

// Build host architecture, matching the existing app build. Release builders
// must compile this alongside each architecture before forming universal apps.
const output = process.argv[2];
if (!output) throw new Error('Usage: build-companion-installer.ts <output executable>');
mkdirSync(dirname(resolve(output)), { recursive: true });
execFileSync(process.execPath, ['build', '--compile', '--target=bun-darwin-' + process.arch,
  resolve(import.meta.dir, 'companion-installer.ts'), '--outfile', resolve(output)], { stdio: 'inherit' });
