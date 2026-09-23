# Lattices disk image

The release builder calls `package.sh` after assembling and signing the app.
Install its packaging dependency with `brew install create-dmg`.

To inspect the design without compiling or replacing the installed app:

```sh
tools/release/dmg/package.sh /Applications/Lattices.app /tmp/Lattices-preview.dmg
```

This preview contains the supplied app unchanged. It is not a new app release;
the packaging helper does not sign or notarize the image. The release builder
retains those steps after packaging.

`render-background.swift` renders the warm white background at 2x resolution
with native typography and the existing nine-cell L mark. Finder supplies the
real draggable app and Applications shortcut. Keep icon positions synchronized
with the arrow at (340, 235). The window includes room for Finder tab chrome.

Design: one installation action, large recognizable app/folder targets, quiet
instructions, and a separate next step after copying. No installation commands
are baked into the image; alternate setup paths live in the site's install section.
