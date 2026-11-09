# Review r1 of build K (fresh reviewer, 2026-11-09)

Served `docs/design/landing-polish` over http, shot with the cached headless Chromium at 1440×900 (first screen, full page, hero at +1.5/3/6 s, Mail demo mid-run, reduced motion), 1024, 768, 390, 320, plus each section at 1440 and 390. Zero console errors and no sideways scroll at any width. Every number checked against `README.md`, `docs/site/compare/README.md` and `docs/site/a2/index.html` `#cost`.

## Scores

| Area | Score | Why |
|---|---|---|
| Polish / craft | **6** | Hero is strong, but: ~12 distinct text sizes (13/14/15/16/18/19/20/22/26/56/96 + mono 13/14/15), not 3–4; the brew line and `<code>` in the how-line render in **Courier** (UA `monospace`), not SF Mono; the close section's blurred arch paints **over** "Type half." and the buttons (washes them grey); the one-section-per-screen rhythm leaves 200–450 px of dead cream in Keys, Korean and FAQ at 1440×900; the settings screenshot is cropped through a line of text at its bottom edge; Instrument Serif has no U+2011, so "mid‑syllable" falls back to a wide system hyphen. |
| Brand | **8** | Cream, ink pills, frosted field, glass suggestions, blurred arch, the icon in the close: reads as the app. Off notes: section 2's lead says "Grey text" while every suggestion on the page is glass; the "Yes" in the Korean table is a flat `#2f6aa8` blue, not the glass. |
| Message | **8** | In 5 s: what it is (headline + live field), Mac (eyebrow), how to get it (Download + brew). Lead is 18 words. The hero shows the same three sentences twice (ribbon and field), which dilutes rather than adds. |
| Motion | **7** | One signature motion per section, pause button, IntersectionObserver, reduced motion gives finished stills. But the ribbon drift is `<animate>` with default linear `calcMode` and never rests; the Mail demo replays the hero's exact script, so the second section feels like a repeat rather than a new moment. |
| Honesty | **6** | Two misses against rule 7 / section 7: the **21.6% / 81.5% / 53 ms strip is missing** (with its "replayed with real typing delays, before the latest change to suggestion length" line), and the Cotypist memory tip still says **"478 MB in a second run"** (a2 and compare/README say *first* run). Smaller: Team chat's ghost drops the "!" the demo has. Everything else matches (0.53/1.27/2.98/3.85 GB, 79/185/383 MB, 0.2/0.2/2.2%, 0.69 keys, the how-measured line verbatim, privacy lines). |
| Responsive / solid | **6** | 768: the Mail window covers the Messages window's suggestion in section 3. 390: chart values wrap ("0.53 / GB") in a 56 px column. 320: the brew command truncates to "brew install --cask ha…", the one line people copy by eye. Pause button is 32×32; nav links 36 px tall. 768: three charts in a 2-column grid leave CPU orphaned on its own row. Glass text ≈3:1 (acknowledged in NOTES). |

**Average 6.8; three areas under 7. Not at the bar yet.**

## Changes, most impactful first

1. **Honesty: add the stats strip and fix the Cotypist tip.** In `#cost` after `.vs__how` (or between the head and `.vs`), add a 3-up strip: **21.6%** "of keystrokes saved across whole messages", **81.5%** "of suggestions right on the first word", **53 ms** "to the first word", serif numerals at `--t-h2`, with one mono line under it: "English, default settings, replayed with real typing delays, before the latest change to suggestion length. How it's measured" → `docs/measuring.md`. Line 396: `478 MB in a second run` → `478 MB in a first run`.
2. **Close: put the arch behind the content.** `.close .arch { z-index: -1; }` (`.close` already has `isolation: isolate`). Today "Type half." and the Download pill are washed out by the blur sitting on top of them. Check `.keycard .kc` too: it has `z-index:1` but no `position`, so the z-index does nothing; add `position: relative`.
3. **Mono font.** `.brew code, .vs__how code { font: inherit; }` so they use `--font-mono` (SF Mono / Menlo) instead of the UA's Courier. Visible in the hero's first screen.
4. **Kill the dead air.** Drop the forced 100svh per section for Keys, Korean and FAQ (let them be content-height with 128 px section padding), or give them content that fills it: Keys cards could each play their one keypress (glint on Tab), FAQ can sit in one column under its head. At 1440×900 Keys has ~170 px empty above the cards and ~200 below; FAQ ~450 below.
5. **768 apps overlap.** At `max-width:1023px`, either stack like the phone layout or set `.w-mail { top: 38% }` and `.w-chat { bottom: 4% }` so no window covers another's caret line. A suggestion hidden under a window defeats the section.
6. **Phone chart values.** `@media (max-width:639px) .vs__bar { grid-template-columns: 64px 1fr auto; }` and `.vs__val { white-space: nowrap; }`.
7. **320 brew line.** Below 360 px drop to 12 px mono and `letter-spacing:-.02em`, or let it wrap to two lines; never ellipsize the command.
8. **Type scale.** Collapse to display (serif clamp 40–96), h2 (serif 36–56), body 17 (lead and body the same size, colour separates them), label 13 mono. Remove 14/15/19/20/22/26 one-offs: `.vs__name`/`.vs__val` 14 → 13 mono; `.say` 15 → 16; `.ko .ht-text` 26 → 22 like the hero field; `.vs__ko` 15 → 16.
9. **Copy: "Grey text finishes your sentence."** → "Coloured text finishes your sentence. Tab takes it." (or just "Tab takes the rest."). Grey is what macOS's own predictions look like; ours are glass.
10. **Hero: let the ribbon breathe.** Ribbon text runs right under the buttons at 1024 and behind the field at every width; drop it to `opacity:.7`, start it lower (`.ribbon { height: min(440px, 44svh) }`), and either ease the drift (`calcMode="spline"` with a slow ease, or a pause between messages) or stop it after one pass. Consider showing the messages only on the ribbon *or* the field, not both.
11. **Section 2 demo.** Give the Mail window its own sentence set (still from `demo.sh`'s script, e.g. start with "Thanks for the update…") so it doesn't repeat the hero beat-for-beat; trim `.mail .ht-text` bottom padding 96 → 48 so the window doesn't look half empty, and enlarge `.mail` to ~720 tall feel at 1440.
12. **Privacy screenshot.** Crop `window-settings.png` at a section boundary (after "Hide the suggestion") so no line is cut, or mask its bottom with a fade.
13. **Tap targets.** `.loop-pause` 32 → 44 px (or a 44 px `::before` hit area); `.nav__link` min-height 44.
14. **"mid‑syllable".** Use a plain hyphen with `white-space: nowrap` on a span instead of U+2011, which Instrument Serif lacks.
15. **768 compare grid.** `.vs { grid-template-columns: 1fr; }` below 1024, or 3 columns with smaller bars, so CPU isn't orphaned.
16. **Korean table "Yes".** Use `.glass-text` with weight 600 instead of `#2f6aa8`.
17. Team chat ghost `hope you have a great day` → `hope you have a great day!` (line 321) to match the demo.

## Not checked
Real Safari (ui-monospace, backdrop-filter, SVG textPath rendering), keyboard-only walkthrough, the clipboard write.
