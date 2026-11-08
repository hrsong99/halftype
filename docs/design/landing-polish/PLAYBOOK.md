# Building halftype.app's polished page (round 2 of landing-polish)

## State (keep this current)
- 2026-11-09: John picked "C + D + J" from `index.html` ("Sure looks good, go ahead and build that"). Round 1: H 7.0, K 6.8 (review-r1.md in each folder); both under the bar. Hand-built wins the method test (K's lowest scores came from the kit: type sizes, Courier, one-screen sections). Round 2: H 7.5 (review-r2.md), nothing under 7. Round 3: H 8.5 (review-r3.md), nothing under 8: at the bar. Codex code review found 5 P2s (contrast 2.0-2.6:1, reduced motion at runtime, per-card triggers, off-screen work, clipboard fallback). Fix round done; Codex re-review clean (one stale path, fixed). Result in round2.html; waiting on John to publish.
- Nothing goes on halftype.app until John sees the result. Publishing is his call.

## Goal, in John's words
- "Not a bad start but definitely not professional polish level yet." The bar is the references in `references/`: Raycast, Linear, Wispr Flow, Dia, Cursor, Things, CleanShot X.
- "this is no longer the app design language": the page must look like today's app.
- "We should probably cut down on so much of the korean stuff, our first audience will be english."
- "You can use the example in the readme can't you? And remove the not always this good, or on sentences it does well (they are in fact from my own experience)."
- "A looks best but it has some overly long ux writing."

## Rules (from John and the repo)
1. **The app's look, exactly.** Cream `#f6f1e9`, ink `#1d1c1a`, the icon's arch (`arch.svg`) blurred behind things, a frosted white field (`rgba(255,255,255,.6)`, blur, radius 20), and suggestions in the glass gradient `#5f9bd8 → #99b0c9 → #e88f5e`. A Tab plays a 0.25 s glint over only the letters it took. The app icon is `icon.png`, the mark is in `demo.js`. Ink buttons. Colours and shapes come from `Sources/HalftypeApp/Window.swift` and `GhostPanel.swift`. No halftone sky anywhere.
2. **Type.** System font (SF) for text and UI. Instrument Serif (Google Fonts) only for display headlines, as in option C.
3. **The demo is the README's.** Use `demo.js`'s `runDemo` (its messages, suggestions and Tab / Shift-Tab rules come from `scripts/demo.sh`). Don't add a disclaimer about the suggestions.
4. **Short copy.** A hero lead of 20 words or fewer. Card titles with no sentence under them, or one short one. FAQ answers on one line. Detail lives in the README; link to it.
5. **English first.** One Korean section (finishing mid-syllable: `만나서 반갑` + glass `습니다.`, and the keys Tab presses: ㅅ ㅡ ㅂ ㄴ ㅣ ㄷ ㅏ .) and one Korean FAQ answer. No Korean summary section.
6. **Every claim and number comes from `README.md`** and carries how it was measured, here or by a link to `docs/measuring.md`. No invented users, quotes, logos or numbers. Privacy lines are promises: one permission (Accessibility, no Screen Recording); network only for model downloads (Hugging Face, SHA-256 checked) and a daily update check; on disk only settings, models and four counts a day, no text, no logs; secure fields skipped.
7. **The comparison** comes from `docs/site/a2/index.html`'s `#cost` section and `docs/site/compare/README.md`: download size, memory at rest, CPU at rest, and the Korean row, with the same how-measured line (KeyType left out at rest, and why). You may redesign how it looks; don't change a number or drop a qualification.
8. **Install:** "Download for Mac" → `https://github.com/hrsong99/halftype/releases/latest/download/Halftype.dmg`. Homebrew as one small mono line (`brew install --cask halftype`) with a copy button that copies both lines: `brew tap hrsong99/halftype && brew trust hrsong99/halftype` and `brew install --cask halftype`. macOS 26, Apple Silicon. Free, MIT.
9. **Static, light, fast.** One HTML file plus the files it needs, in the worker's folder. No framework, no build step. Scripts only from cdnjs/jsdelivr if needed at all (prefer none). Total under 1.5 MB with images.

## Rules added after round 1 (both reviews found these)
10. **Each sentence once.** The hero's ribbon and field must not show the same sentences at the same time. Prefer: the ribbon still, or stepping to the field's current message, and always clear of the field at every width.
11. **Section 2 is not a second copy of the hero.** One short Tab / Shift-Tab beat (about 6 s) that starts when the section scrolls into view, with its own lines. Static windows in section 3 use their own short lines too. New example lines are invented, ordinary messages (never anyone's real text).
12. **At most 5 text sizes on the page**, counted with `getComputedStyle` over every text node; set `font-family` on `code`, `pre` and `kbd` so no UA Courier shows.
13. **Sections fit their content.** No section is padded to a full screen around a small block; target 96–160 px of air between sections at 1440.
14. **Qualifications survive every width.** Never hide a column, note or line that qualifies a claim on smaller screens; reflow it instead.
15. **Claims about where it works** quote the README: Chromium apps "used by hand in T3 Code", nothing broader.
17. **The Korean row carries its cost**, as the README does: mid-syllable suggestions saved 0.69 keys per request, and 18.2% of them were wrong, against 8.4% without.
18. **No placeholder bars.** Every window shows real (invented) labels and messages, never grey skeleton lines.
16. **Every animation pauses** off screen and with one visible pause control; tap targets 44 px including that control.

## The page, top to bottom
1. **Hero (option C, `C.html`).** "You type half. *It writes the rest.*" in Instrument Serif, the second line in glass. One short lead. Download button, mono brew line. The demo's messages flow along the arch path (SVG `textPath`), typed part in ink, suggested part in glass, while the frosted field below runs `runDemo`. Nav: mark + Halftype, 3–4 links, a small Download.
2. **In a real app (option D, `D.html`).** A Mail compose window on the blurred arch, the demo typing in its body, a large Tab keycap that presses. Optionally cycles Mail → Messages → a chat app (no real logos).
3. **Every app (image idea J, `images/J.jpg`).** Several small Mac windows (Messages, Mail, Notes, a team chat; no logos) at different depths, each with a sentence and a glass suggestion after its caret, joined by the ribbon drawn as a glass tube. Build it in HTML/CSS/SVG, not as a picture.
4. **Three keys.** Tab takes a word, Shift-Tab takes it all, Esc hides it. Small live or still demos, not paragraphs.
5. **Korean, mid-syllable** (rule 5).
6. **Privacy** (rule 6), with today's settings screenshot `docs/site/a2/img/window-settings.png` or something better drawn in HTML.
7. **Compare** (rule 7), with a strip of Halftype's own figures: **21.6%** of keystrokes saved across whole messages, **81.5%** of suggestions right on the first word, **53 ms** to the first word (English, default settings, replayed with real typing delays, before the latest change to suggestion length; link `docs/measuring.md`).
8. **Limits / FAQ**, short.
9. **Close:** big serif line, Download, mono brew line, then a quiet footer (GitHub, How it works, Releases, MIT).

## What good looks like (the checklist every worker self-checks, and the reviewer scores)
- **Polish (craft):** an 8 px spacing system; one container width; consistent radii (20 field, 12–14 windows, 999 pills); type scale with 3–4 sizes; optical alignment; no orphan words in headlines; shadows soft and few; nothing looks default.
- **Brand:** reads as the same product as the app window and icon at a glance.
- **Message:** in 5 seconds a stranger knows what it is, that it runs on the Mac, and how to get it.
- **Motion:** one signature motion per section at most; easing, not linear; nothing loops faster than 6 s except typing; `prefers-reduced-motion` shows still, finished states; no layout shift; no scroll-jacking.
- **Honesty:** rules 3, 6 and 7 hold; nothing invented.
- **Responsive and solid:** 1440, 1024, 768, 390 and 320 wide with no sideways scroll or overlap; tap targets 44 px; text contrast AA; alt text; focus rings; zero console errors.

Score each 1–10. **The bar: an average of 8, nothing under 7.** At most 3 review rounds per worker.

## Steps for a worker
1. Read this file, `index.html`'s options C and D (`C.html`, `D.html`), `images/J.jpg`, `base.css`, `demo.js`, the references in `references/`, `README.md` and `docs/site/a2/index.html`.
2. Build in your folder only (`builds/<you>/`). Copy what you need from `base.css`, `demo.js`, `arch.svg`, `icon.png` into it; don't edit the shared files. Need a shared change? Say so in your report.
3. Check: serve the folder over http, then screenshot 1440×900 (first screen and full page), 1024, 768, 390 and 320 wide with the cached headless Chromium (`/Users/johnsong/Library/Caches/ms-playwright/chromium_headless_shell-1248/chrome-headless-shell-mac-arm64/chrome-headless-shell`, Playwright module at `/Users/johnsong/.npm/_npx/dd4723f69cd11a73/node_modules/playwright/index.mjs`). Record console errors and sideways overflow. Look at every screenshot against the checklist and fix what you see. Save the final shots in `builds/<you>/shots/`.
4. Write `builds/<you>/NOTES.md`: your decisions, what you'd still change, and anything you couldn't check.
5. Don't commit, push, deploy, open windows or apps, or take focus. One headless browser at a time.

## Methods being compared (round 1)
- **K, kit:** start from `docs/site/a2/index.html` and the TasteSkill kit it uses (`docs/site/a2/assets/`), restructure it into the sections above.
- **H, hand-built:** start from a blank file with `base.css` and `demo.js`; no kit. Own small CSS.

## Process (what changed and why)
- 2026-11-09: playbook written after round 1 of `index.html` (variants) and John's pick.
- 2026-11-09, after round 3: the supervisor decided the page's suggestion gradient uses darker stops (4.5:1) than the app's, for accessibility; the app is unchanged.
- 2026-11-09, after round 2: rules 17 (Korean cost) and 18 (no skeleton bars) added; compare/README's Cotypist CPU line corrected to "one 13% sample in each of two 8-minute runs".
- 2026-11-09, after round 1 reviews: rules 10–16 added; each was found in both K's and H's review, so it was the playbook's gap.
- 2026-11-09, after round 1 builds: K dropped the 21.6% / 81.5% / 53 ms figures because the section list had no place for them; added to section 7. H found a2 called Cotypist's 478 MB a "second run" (it was the first); fixed in a2 and on halftype.app.

## Process (how this was made, to rerun it)
1. One variants round (`index.html`) of visibly different first screens, built on shared `base.css` / `demo.js`, plus Codex image ideas; John picked C + D + J.
2. This playbook, then two competing methods on the same brief (K: the TasteSkill kit; H: hand-built). A fresh reviewer per build per round wrote `review-rN.md`; makers never graded themselves.
3. Results: H 7.0 → 7.5 → 8.5; K 6.8, cut after round 1. The kit cost points it couldn't win back (type sizes, UA Courier, one-screen sections), so hand-built on the app's tokens is the method for this site.
4. Every problem both reviews found became a rule (10–16), and later ones 17–18, before the next round.
5. At the bar: a Codex code review (5 P2s: contrast, reduced motion at runtime, per-card triggers, off-screen work, clipboard fallback), one fix round, a Codex re-review (clean).
