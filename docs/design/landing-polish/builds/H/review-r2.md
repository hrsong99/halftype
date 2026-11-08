# Review of H, round 2 (fresh reviewer, 2026-11-09)

Read PLAYBOOK.md and the references (Wispr, Linear and others) first, scored the page, then read NOTES.md. Served `docs/design/landing-polish` over http and screenshotted it with the cached headless Chromium: 1440×900 (first screen, full page, reduced motion, paused), hero field at 0.7/2.5/4.5/7/10/14 s, the Mail beat at 0.3/1.5/2.4/3.3/4.5/7 s and the Korean beat at 0.5/2.7/3.3/4.3/6 s, then 1024, 768, 390 and 320 full pages. Measured on every width: console errors, scrollWidth, text sizes, tap targets and the keyboard tab order.

## Scores

| Area | Score | One line |
|---|---|---|
| Polish (craft) | **7** | Tokens and spacing are disciplined. But the section 3 windows are grey skeleton bars, the close section is mostly empty, and phones show orphans and an empty Korean field. |
| Brand | **8** | Cream, ink, the arch, the frosted field, glass suggestions, the glint and the icon. It reads as the app at a glance. |
| Message | **8** | In 5 s: what it does, that it's for the Mac, the Download button and brew. The hero fits above the fold at 1440 and 1024 (field bottom at 837 / 785). |
| Motion | **7** | One motion per section, each started on view and pausable, and the glint is right. But reduced motion still shows a pause button that does nothing, and the hero's only motion is small. |
| Honesty | **8** | Every number checks out against README.md, compare/README.md and a2. One Cotypist CPU wording differs between the two sources. |
| Responsive / solid | **7** | No overflow and no console errors at any width, and focus rings work. But 390/320 have layout flaws, the glass text is below AA, and the pause button ignores `hidden`. |

**Average 7.5: under the bar.** Nothing is under 7, but the average is short of 8, and three areas sit at exactly 7. Up from 7.0 in round 1.

## What I checked, and what held

- **Numbers.** 0.53 / 1.27 / 2.98 / 3.85 GB, 79 / 185 / 383 MB (478 in a first run), 0.2 / 0.2 / 2.2% and 0.13–0.27% all match compare/README.md and a2. 21.6% (real typing delays, before the length change), 81.5% (2,400 held-out requests), 53 ms (median of requests that reached a first word), 0.69 keys mid-syllable, and "about a fifth" all match README lines 50–71. The Chromium line quotes README line 99. The privacy rows match README lines 76–80. The KeyType at-rest exclusion and why are kept. Nothing is invented: names (Priya Shah) and lines are ordinary made-up ones.
- **Rule 12:** 5 sizes at every width (13, 15, 19, h2 clamp, display clamp), with mono on `code` and `kbd`. No Courier.
- **Rule 10:** the ribbon is still and ends 24 px above the field (ribbon bottom 672, field top 696 at 1440). No sentence repeats.
- **Rule 14:** the Korean table reflows on phones, and every note stays visible.
- **Rule 16:** pausing works. The hero text stayed identical for 1.5 s after the click, and demos idle off screen.
- **Keyboard order:** logo, the four links, pause, Download, Download for Mac. Correct.
- **Console errors:** 0 at every width.

## NOTES.md claims vs what landed

| Claim | Landed? |
|---|---|
| Ribbon still, own lines, 24 px clear of the field | Yes |
| One Mail beat with its own line, about 7 s, started on view | Yes. Typing, then Tab takes "ursday" with the glint, then Shift-Tab takes the rest. |
| Section 3 with its own lines, and a tube | Lines yes. The "tube" reads as a background blur with a faint 2 px streak, not a glass tube. |
| Key cards show before, the key, after | Yes |
| Pause "Hidden under reduced motion" | **No.** `pauseBtn.hidden = true` is set, but `.pause { display: grid }` overrides `[hidden]`. Measured: `hidden=true`, `display: grid`, and the button is visible in reduced-1440. |
| 5 text sizes, no Courier | Yes |
| Sections 128 px apart | Yes between sections. The FAQ → close gap is about 330 px (64 + 128 padding, plus the icon). |
| Privacy image hidden at ≤600 | Yes. That's allowed, since it isn't a qualification, but phones then lose the only real app UI on the page. |
| NOTES headings | Stale. The file still opens "(round 1)", and the round-1 Decisions describe things that are gone: section 2's per-message title swap, Esc struck through, the 48 s ribbon loop. |

## 1. Polish (craft): 7

Good: the 8 px scale is used throughout, one 1120 container, radii stay at 20 / 14 / 999, shadows are soft and few, and the hero is calm and well balanced at 1440 and 1024.

What holds it under 8, most visible first:
1. **The section 3 windows are wireframes.** Grey 10 px pills for sidebars, grey and blue blobs for bubbles, two grey bars for chat history (`.side b`, `.bub`, `.line`). Next to Linear's and Raycast's real-looking UI, this reads as a placeholder. Each window needs a few real, short, invented lines of content.
2. **The close section is mostly air.** At 1440 there is about 330 px from the last FAQ row to the icon. The arch blobs behind it (`.close .arch`, `top: 40%`, 700 px tall) are cut off in a hard line at the footer, and the peach blob at the bottom right is visibly chopped.
3. **The Mail stage is a beige box** (`.stage { background: var(--soft) }`), the only boxed hero-style panel on the page. Everything else floats on cream, so it reads as a different design.
4. **Phones:** the Korean field gets `.field .text { min-height: 4.35em }` from the hero's ≤600 rule, so it's a tall, mostly empty card (390 px shot). The jamo row wraps "." alone onto a second line. "Updates itself" breaks to "· Updates / itself" at 320. The footer links wrap "MIT licence" alone, with a big gap under the logo.
5. **The ⇧ glyph in keycaps is about half the cap height** (SF Mono falls back). It shows in the hero key, the Mail key and the Shift-Tab card.
6. **`models.png` text is about 10–11 px** once scaled to 528 px, the smallest text on the page, and it's a bitmap, so it's soft next to the live type.

## 2. Brand: 8

The cream, the glass gradient on the headline's second line, the frosted field with the model pill and power button, the icon in the close, and the arch blur all match `Window.swift` / `GhostPanel.swift`. The glint plays over only the taken letters, as in the app.

To reach 9:
- **The key cards' "after" state uses a 2 px glass underline** (`.took`), but the hero and Mail use the letter glint (`.taken`). Two different marks for "taken" is off-brand. Use `.taken`'s finished state: ink letters, with the glint replayed when the card scrolls into view.
- **The footer mark is 18 px and faint** at 1440. Use the 22 px mark from the nav.

## 3. Message: 8

"You type half. It writes the rest." plus a 17-word lead plus Download says what, where and how within 5 s. The eyebrow "For macOS 26 on Apple Silicon" answers "for me?".

To reach 9:
- **The hero field's demo starts empty** for about 0.3 s each loop (hero-14000 shows a blank field with a caret). A first-time visitor who looks at the field at that moment sees nothing. Start each loop with the first letters already typed, or hold the finished message longer (it holds 1.6 s now).
- **Korean isn't hinted at above the fold** although it's the README's first claim. That's fine under rule 5 for an English audience, but the eyebrow could end "· English and Korean" at no cost.

## 4. Motion: 7

Good: one motion per section, eased key presses, the glint, the Mail beat at about 6.5 s and Korean at about 7 s (both 6 s or longer), start on view, off-screen idle, and one pause control.

Under the bar because:
1. **Reduced motion still shows the pause button** (bug above). Fix: add `.pause[hidden] { display: none; }`.
2. **The hero has no signature motion beyond typing in a 640 px box.** The still ribbon is texture, but at 1440 it's a 1440-wide band that never moves, while Wispr's equivalent band is the motion. A very slow (60 s or longer), eased drift of `startOffset`, paused with everything else and still under reduced motion, would fix this. It was in round 1 and taken out under rule 10. The rule is about the same sentences showing at once, which the separate ribbon lines already avoid, so a drift is allowed.
3. **The key cards are fully still** while the cards beside them in the README are about keys being pressed. One press per card when the row scrolls into view (key goes down, then the after state appears with the glint, once, not looping) would make section 4 land.

## 5. Honesty: 8

Every number and qualification holds (see "What I checked"). To reach 9:
1. **Cotypist CPU wording.** The page (and a2) say "one sample of 13% in each 8-minute run". compare/README.md line 11 says "13% about every 5 min". They aren't the same claim. Pick the one the data supports and make a2, compare/README.md and this page agree.
2. **The Korean row's "0.69 keys saved per mid-syllable request"** drops the cost README line 52 gives with it: "18.2% of those requests [wrong], against 8.4%". Add "; more wrong suggestions (18.2% vs 8.4%)" to that cell, or link it. The same row in a2 has the same gap.
3. **The models screenshot shows Gemma 4 E2B at 3.4 GB, while the chart calls Gemma 4 E2B 2.98 GB** (Cotypist's quant). The chart note covers it ("as Cotypist downloaded it"), but a reader comparing the two will stumble. Either crop the screenshot above Gemma or add "Q4_C" to the chart note.

## 6. Responsive / solid: 7

Good: no sideways scroll (scrollWidth equals the viewport at 1440/1024/768/390/320), 0 console errors, `:focus-visible` rings, alt text and `role=img` labels, `lang="ko"`, a sensible tab order, and the nav collapses to logo, pause and Download.

Under the bar because:
1. The **pause `[hidden]` bug** (see Motion).
2. **The glass suggestion text is below AA** (about 2.2:1 for `#99b0c9` on white). NOTES leaves this as a decision for John. Raise it with him explicitly, with the 19 px mitigation stated.
3. **The phone flaws** from Polish 4: the empty Korean field, the orphan ".", the "itself" orphan, the footer wrap.
4. **No skip link** past the nav (cheap: `<a class="sr" href="#hero-h">`, shown on focus).
5. **Inline "How it's measured" links are 16–18 px tall.** They're exempt as inline text, but at 390 they are the only path to the method and sit in 13 px type. Make the one under the figures a 44 px `.more`-style link.

## Top changes, most impactful first

1. **Fill the section 3 windows with real UI** (`index.html`, the `.app__body` blocks). Replace `.side b` pills with 3–4 short invented labels (Messages: "Sam", "Alex", "Jo"; Notes: "Weekend", "Groceries", "Trip"; Team Chat: "# general", "# design"). Replace `.bub` blobs with two real 13 px lines ("Game starts at 7?", "Yes! Section B") and `.line` bars with one earlier message. This is the single biggest gap to Linear/Raycast.
2. **Fix the pause button under reduced motion.** In `page.css`, add `.pause[hidden] { display: none; }`.
3. **Fix the phone layouts.** In the ≤600 block, scope the field min-height to the hero: change `.field .text { min-height: 4.35em; }` to `.hero__field .text { … }`. Make the jamo row fit (`.jamo .kc { min-width: 36px; height: 40px }` at ≤600, or `flex-wrap: nowrap` with a `gap: 4px`). In `.fine`, use `·&nbsp;Updates&nbsp;itself`. In `.foot__in` below 600, `flex-direction: column; align-items: flex-start` with links in one row.
4. **Tighten and finish the close** (`.close`). Change padding to `var(--s7) 0 var(--s8)` and the section above to `padding-bottom: var(--s5)`, so the gap from the FAQ is about 160 px. Contain the arch: `.close .arch { top: 20%; height: 520px; }`, plus `mask-image: linear-gradient(#000 60%, transparent)` so it fades instead of being cut at the footer.
5. **Give section 4 one press per card on view.** When `.keys` intersects, each card in turn presses its key (`.kc.down`, 180 ms), then swaps to its after state with `.taken` (the real glint) instead of the `.took` underline. Play it once, not looping; under reduced motion show the after states.
6. **Reconcile the Cotypist CPU wording** across a2, compare/README.md and this page, and add the 18.2% vs 8.4% cost to the Korean row.
7. **Hero: a slow drift on the ribbon** (`startOffset` over about 60 s, eased, paused by the pause control and off under reduced motion), so the first screen has one signature motion, not just a typing box.
8. **Unboxed Mail stage.** Drop `.stage`'s `background: var(--soft)` and the radius, and let the window sit on the arch directly on cream, like section 3.
9. **Small:** the ⇧ glyph at the text's size (`<span style="font: 600 1.1em var(--sans)">⇧</span>`), the footer mark at 22 px, and update NOTES.md's stale round-1 lines.

Not checked: Safari and real backdrop-filter, the real clipboard, a screen reader pass.
