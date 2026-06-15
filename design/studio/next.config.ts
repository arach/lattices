import type { NextConfig } from "next";
import path from "node:path";
import { fileURLToPath } from "node:url";

// This app lives at ~/dev/lattices/design/studio but consumes `studio` and
// `hudsonkit` from sibling repos (~/dev/studio, ~/dev/hudson) via the studio
// bun workspace. Pin Turbopack's root to the common ancestor (~/dev) so it can
// resolve the symlinked packages instead of mis-inferring the workspace root.
const here = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  turbopack: { root: path.resolve(here, "../../..") },
  transpilePackages: ["hudsonkit", "studio"],
};

export default nextConfig;
