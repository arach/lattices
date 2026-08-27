# Agent Recording Notes

## Stable Path

`record-region` and `record-app-window` currently work by:

1. host receives command
2. host contacts local agent
3. agent launches `Action.app` in `recording-probe` mode
4. probe performs actual `WindowRecorder` work
5. probe writes `.finished`

## Debug Checklist

- confirm `.mov` exists
- confirm `.finished` exists
- inspect `--debug-log` output
- verify the signed app bundle was used

## Do Not Regress

- do not move recording back into a plain headless lifecycle
- do not assume initial `"recording"` means completion
- do not bypass the probe launcher unless replacing it with another lifecycle-safe AppKit path
