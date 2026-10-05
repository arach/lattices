// Recompose the generated masters without editing them. Requires ImageMagick.
import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
const base=fileURLToPath(new URL('.',import.meta.url));
const temp=mkdtempSync(`${tmpdir()}/ply-contact-`);
const poses=[['01-idle','Idle'],['02-pick-up','Pick up'],['03-carry','Carry'],['04-wait','Wait'],['05-set-down','Set down'],['06-snap-back','Snap back']];
const run=args=>execFileSync('magick',args,{stdio:'pipe',maxBuffer:1024*1024});
const surfaces=[['dark','#141416','#f2f2f2'],['light','#f2f2f2','#141416']];
const nativeRows=[],proofRows=[];
for (const [name,bg,fg] of surfaces) {
 const nativeCells=[],proofCells=[];
 for(const [id,label] of poses) {
  const file=`${base}/${id}.png`, native=`${temp}/${name}-${id}-native.png`,proof=`${temp}/${name}-${id}-proof.png`;
  run(['-size','1294x1414',`xc:${bg}`,file,'-geometry','+20+65','-composite','-font','Helvetica-Neue','-pointsize','30','-fill',fg,'-gravity','NorthWest','-annotate','+34+18',label,'(',file,'-resize','24x24',')','-geometry','+34+1345','-composite','-font','JetBrains-Mono','-pointsize','15','-annotate','+76+1345','24 px  /  native master above: 1254 x 1254',native]);
  const args=['-size','200x340',`xc:${bg}`,'-font','Helvetica-Neue','-fill',fg,'-pointsize','17','-gravity','NorthWest','-annotate','+20+17',label,'(',file,'-resize','192x192',')','-geometry','+4+44','-composite'];
  for(const [size,x] of [[16,34],[24,84],[32,134]]) args.push('(',file,'-resize',`${size}x${size}`,')','-geometry',`+${x}+253`,'-composite','-font','JetBrains-Mono','-pointsize','11','-annotate',`+${x}+300`,`${size} px`);
  args.push(proof);run(args);nativeCells.push(native);proofCells.push(proof);
 }
 const nr=`${temp}/${name}-native-row.png`,pr=`${temp}/${name}-proof-row.png`;
 run([...nativeCells,'+append',nr]); run([...proofCells,'+append',pr]); nativeRows.push(nr);proofRows.push(pr);
}
run([...nativeRows,'-append','-set','comment','Ply family v1. Built-in generated PNG masters composed at native1254px and actual24px on #141416 and #f2f2f2. Exact generation prompts: prompts.json.',`${base}/contact-sheet.png`]);
run([...proofRows,'-append',`${temp}/size-proof.png`]);
console.log(JSON.stringify({contactSheet:`${base}/contact-sheet.png`,sizeProof:`${temp}/size-proof.png`}));
