import { defineTool } from "eve/tools";
import { never } from "eve/tools/approval";
import { z } from "zod";

import { generateAgentArtifacts } from "../../lib/lattices-docs.mjs";

export default defineTool({
  approval: never(),
  description: "Regenerate Lattices agent-doc artifacts by running the existing site agent-docs writer.",
  inputSchema: z.object({
    repoRoot: z.string().optional().describe("Repository root. Defaults to LATTICES_REPO."),
    distDir: z.string().optional().describe("Output directory. Defaults to apps/site/dist."),
  }),
  async execute(input) {
    return generateAgentArtifacts(input);
  },
});
