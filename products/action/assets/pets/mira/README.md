# Mira Pet Pack

Mira is the Action companion sprite pack in the Lattices-compatible pet format.

Runtime files:

- `pet.json`
- `spritesheet.webp` when copied into `~/.codex/pets/mira` or
  `Action.app/Contents/Resources/Pets/mira`

The source spritesheet currently comes from:

`assets/pets/explorer-cat/sprites/explorer-cat.sheet.webp`

Use:

```bash
bun run mira:install
bun run mira:show -- "Mira online"
```

`mira:show` publishes Mira through Lattices `overlay.actor.publish`.
