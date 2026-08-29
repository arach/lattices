# Action Media Packs

Action keeps optional decoration assets out of the app bundle.

The intended release path is:

1. Keep pack manifests and catalog files in git.
2. Publish binary media packs as GitHub Release assets.
3. Optionally publish this folder with GitHub Pages as a browsable catalog.
4. Cache installed media locally under `~/Library/Application Support/Action/Media`
   or a kind-specific path such as `~/Library/Application Support/Action/Typing`.

Small metadata can be served through raw GitHub URLs. Larger or frequently
changing media should stay in release assets so clone size and git history stay
small.
