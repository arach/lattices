# @lattices/sdk

Typed SDK modules for Lattices.

```ts
import { cua } from "@lattices/sdk";

await cua.magicCursor({
  app: "Scout",
  xRatio: 0.52,
  yRatio: 0.91,
  text: "What are the most important docs in this project?",
  treatment: "execute",
  trail: "comet",
  motion: "rush",
  trajectory: "overshoot",
  glow: "halo",
  idle: "wiggle",
  edge: "ripple",
});

await cua.click({
  app: "Scout",
  xRatio: 0.74,
  yRatio: 0.95,
  transport: "ax",
  axLabel: "Send",
  noFocus: true,
  treatment: "execute",
});
```

You can also import the CUA module directly:

```ts
import { cua } from "@lattices/sdk/cua";
```

This package is the product-facing facade over the Lattices daemon. The
`lattices` CLI remains the human/debug surface; app and agent code should import
SDK modules from `@lattices/sdk`.
