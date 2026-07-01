import { defineTool } from "eve/tools";
import { never } from "eve/tools/approval";
import { z } from "zod";

import { auditAgentDocs } from "../../lib/lattices-docs.mjs";

export default defineTool({
  approval: never(),
  description: "Audit whether Lattices source docs and generated agent-doc artifacts are present.",
  inputSchema: z.object({
    repoRoot: z.string().optional().describe("Repository root. Defaults to LATTICES_REPO."),
    distDir: z.string().optional().describe("Generated site dist directory. Defaults to apps/site/dist."),
  }),
  async execute(input) {
    return auditAgentDocs(input);
  },
});
