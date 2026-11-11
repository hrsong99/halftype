# Ghost fonts in web fields

`page.html`: five fields with different fonts, line spacing and page zoom, all with invented text. Open it with `file://` in ego lite (Chromium) and Safari (WebKit). Click at the end of a field's text, type a word, and screenshot the ghost (`scripts/live-keys.swift`, then `screencapture -R`).

2026-11-11, the build with the unnamed-font check (3da0629), next to 0.1.15:
- `old-A`/`new-A` (Menlo) and `old-D`/`new-D` (Courier New): Chromium names no font, so the ghost went from the system font to SF Mono.
- `old-B`/`new-B2` (Georgia): unchanged. Georgia is about as wide as the system font, so the width can't tell it's a serif.
- `old-E`/`new-E2` (zoom 125%): unchanged and too small. The zoom estimate in `GhostLayout.zoomed` misses it.
- `sf2-B`, `sfold-A` (Safari, both versions): Safari names the font but reports a caret as tall as the line, so with loose line spacing the zoom estimate draws the ghost too big and too high.

Later the same day, with a named font's size trusted (Safari's sizes include page zoom) and its baseline set from the box's bottom: Safari's ghosts are the text's size and within 0.5-1 pt of its baseline in all five fields, also at 125% page zoom (`safari-B-fixed`; `safari-B-sized-only` is the size fix alone, 7 pt high). Field E in Safari, 1.25 times too big in 0.1.15, is right too. Chromium's ghosts sit 1-2.5 pt low (`old-A`): about 1 pt from Chromium rounding its boxes to whole points, the rest from the page's font being unnamed.
