import { auditAgentDocs, collectDocs } from '../lib/lattices-docs.mjs'

const docs = await collectDocs()
const audit = await auditAgentDocs()

console.log(JSON.stringify({
  repoRoot: docs.repoRoot,
  docs: docs.docsCount,
  prompts: docs.promptCount,
  score: audit.score,
  missingSources: audit.missingSources,
  missingArtifacts: audit.missingArtifacts,
  recommendedReadOrder: docs.recommendedReadOrder,
}, null, 2))
