# Ghost fonts in web fields

`page.html`: five fields with different fonts, line spacing and page zoom, all with invented text. Open it with `file://` in ego lite (Chromium) and Safari (WebKit). Click at the end of a field's text, type a word, and screenshot the ghost (`scripts/live-keys.swift`, then `screencapture -R`).

2026-11-11, the build with the unnamed-font check (3da0629), next to 0.1.15:
- `old-A`/`new-A` (Menlo) and `old-D`/`new-D` (Courier New): Chromium names no font, so the ghost went from the system font to SF Mono.
- `old-B`/`new-B2` (Georgia): unchanged. Georgia is about as wide as the system font, so the width can't tell it's a serif.
- `old-E`/`new-E2` (zoom 125%): unchanged and too small. The zoom estimate in `GhostLayout.zoomed` misses it.
- `sf2-B`, `sfold-A` (Safari, both versions): Safari names the font but reports a caret as tall as the line, so with loose line spacing the zoom estimate draws the ghost too big and too high.
