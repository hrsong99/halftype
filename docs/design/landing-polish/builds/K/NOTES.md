# Worker K (kit): notes

Built from `docs/site/a2/index.html` on its TasteSkill kit. Kept: `assets/system.css` (grid, 8px spacing, nav, buttons, FAQ rows, one-section-per-screen rhythm) and `assets/system.js` (phone nav sheet). Dropped the kit's motion, moments (liquid-type), layout, backgrounds and icon files: the page needs none of them. 496 KB served (system.css 103 KB, settings PNG 248 KB, icon downscaled to 256 px, 54 KB).

## Decisions
- Hero = option C: serif headline with the glass second line, an 18-word lead, Download pill and a mono brew pill whose Copy copies both brew lines. The ribbon is the arch path in SVG with the README demo's three messages on a `textPath` (typed part ink, suggested part glass), drifting one full cycle per ~50 s (period measured from the text, so the loop has no jump). The field runs `runDemo`. Ribbon height is `min(520px, 52svh)` so it never crosses the buttons on short screens.
- One pause button (WCAG 2.2.2) stops the ribbon and both typing demos. Demos also pause off screen (IntersectionObserver).
- Section 2 = option D: a Mail compose window on the blurred arch, the demo typing in its body, a 1.5x Tab keycap that presses.
- Section 3 = image J in HTML/SVG: three windows (Messages, Mail, Team chat; no logos) at slightly different scales and depths, joined by the arch drawn as a glass tube (blurred gradient + core + white highlight). Lines are the README demo's own. Four windows looked cluttered; Notes was dropped and the heading names no app.
- Keys: each card is before → key → after, as stills. Korean: the field and the jamo keys, still. No motion in sections 3–9.
- Serif (Instrument Serif) for h1/h2/close only; system font elsewhere. Sizes: display clamp(40–96), h2 clamp(36–56), lead 18, body 16, labels 13 mono.
- Compare: numbers, tips, table and the how-measured line copied verbatim from a2's `#cost`; bars restyled (glass for Halftype, warm grey for others), one card per chart.
- `demo.js` is a copy of the shared one with pause/play and a reduced-motion still added.

## Would still change
- The one-screen-per-section rhythm leaves air around short sections (Keys, Korean) at 1440×900; a reviewer may read it as empty.
- The 21.6% / 81.5% / 53 ms stats from a2 aren't on the page (the playbook's section list has no slot); they'd fit as a strip under Compare.
- Glass suggestion text is about 3:1 on cream, under AA for body text. It's the app's look, inside `role=img` figures with alt text.
- The tube in section 3 is soft; a sharper glass highlight would read closer to J.jpg.

## Not checked
- Real Safari/macOS rendering (headless Chromium only); the Copy button's clipboard write; keyboard-only run-through beyond focus rings from the kit.
