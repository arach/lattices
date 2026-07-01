import { defineTool } from "eve/tools";
import { never } from "eve/tools/approval";
import { z } from "zod";

import { readDocArtifact } from "../../lib/lattices-docs.mjs";

export default defineTool({
  approval: never(),
  description: "Read one source markdown doc by slug, for example agents, api, or agent/cua-implementation.",
  inputSchema: z.object({
    repoRoot: z.string().optional().describe("Repository root. Defaults to LATTICES_REPO."),
    slug: z.string().min(1).describe("Doc slug under docs without .md, for example agents."),
  }),
  async execute(input) {
    return readDocArtifact(input);
  },
});
