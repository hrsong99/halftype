# Review of H, round 1 (fresh reviewer, 2026-11-09)

Served `docs/design/landing-polish` over http and took my own shots (headless Chromium): 1440×900 first screen, full page, hero at +4/+7/+11 s, "Right where you type" ×3, Korean ×2, 1024, 768, 390, 320 (first + full), and 1440 with reduced motion. No console errors at any width. No sideways scroll at any width (the ribbon SVG and `.arch` overflow but are clipped by `overflow:hidden`). Tap targets: nav Download (36 px + 4 px `::after`) and Copy (28 px + 8 px `::after`) reach 44; the only small ones are inline text links, which is fine.

## Scores

| Area | Score | Bar |
|---|---|---|
| Polish (craft) | **7** | 8 |
| Brand | **8** | 8 |
| Message | **7** | 8 |
| Motion | **6** | 8 |
| Honesty | **7** | 8 |
| Responsive / solid | **7** | 8 |
| **Average** | **7.0** | 8, nothing under 7 |

Not there yet: the average is a point short and Motion is under 7. The base is good: the colours, the field, the serif and the compare section are right. What holds it back is **repetition** (the same three README sentences appear 5 times, 3 of them animated), **a hero that tangles** (the ribbon runs behind and into the field), and **section 3's tube**, which reads as a neon pipe rather than the app's glass.

---

## 1. Polish (craft): 7

Good: one 1120 container, an 8 px token scale (`--s1…--s8`), radii held to 20 / 14 / 999, soft shadows, balanced headlines with no orphans at 1440. The compare cards and the privacy rows are the best-made parts of the page and come close to Linear's level.

Holding it back:
- **Section 3 ("In almost every app") tube.** At 1440 the SVG tube is a thick neon pipe with two hard round ends floating in space (top right above the Mail window, bottom left under Team Chat). It doesn't look like glass or like the icon's arch, and it's the least refined object on the page. At 390 the windows stack and the tube becomes blue/orange smudges peeking out at the edges.
- **Section 2 ("Right where you type") window is mostly empty.** A 720 px window with a 24 px sentence and about 120 px of blank body. The `tab` keycap sits half off the window's corner. Next to D's Mail compose and the references (Wispr's app shots, Raycast's window), it reads as a wireframe.
- **Three keys cards are flat and alike.** Three identical beige tiles, the field at the top, a small keycap under it, the title outside the card. The Esc card's struck-through ghost (`.ghost.gone`, opacity .25) is nearly invisible, so the card shows "Running 10 m" and nothing else.
- **Type scale.** Defined as 4 sizes, but the page uses about 9 (92/56 serif, 24, 20, 19, 17, 15, 14, 13, 12). The lead (19), ribbon (19), field (20), real window (19) and mini cards (17) are all near-misses of one another.
- **FAQ "How it's measured" link** (`.faq dd a { margin-left:4px; display:inline-block }`) wraps to its own line, indented by 4 px, at 1440.
- **Privacy screenshot** (`img.shot`) is a 1800 px PNG scaled to about 550 px: its text is 6–7 px and unreadable at every width, and at 390 it's a grey smear.

Changes, most impactful first:
1. **Redraw the section 3 tube as the arch, not a pipe.** In `svg.tube`, drop the 36 px solid stroke and the white 6 px stroke. Keep one wide (100–140) blurred stroke at about .55 opacity, exactly like the hero's `#arch` path, and let both ends run off the container (start x<0, end y<0) so there are no round end caps. If you want "glass", add one 2 px `rgba(255,255,255,.6)` highlight that is also blurred (stdDeviation 2). At ≤960 hide `.tube` and put one `.arch` behind the stack instead.
2. **Fill the section 2 window.** Give `.win--big` real content: a Mail compose window (To / Subject rows already exist in `.hdr`, plus a quoted previous message in muted text under the body, or a Messages thread with two bubbles above the composer). Set `.win__body .text` min-height to about 2.5em and let the context fill the rest. Move `#real-key` so it overlaps the window's bottom edge by half its height, centred under the caret line, or sits outside the window entirely, not half on its corner.
3. **Make the three key cards show the result.** Each `.mini` shows before → after in two lines: Tab card "Ha|ppy birthday" → "Happy |birthday" with the glint on "ppy"; Shift-Tab card → the whole sentence in ink; Esc card → "Running 10 m|" with no ghost, plus a tiny "hidden" caption. Delete the `.ghost.gone` strike-through. Put the `h3` inside the card, top left, so the card and its label read as one object (Raycast's feature tiles).
4. **Collapse the type scale** to 4 text sizes: 19 (lead, demo text everywhere), 17 (body), 15 (UI: tables, chart rows, keycaps), 13 (notes, eyebrow). Hero field, real window, Korean field and mini cards all use 19 (Korean 22 is fine as the one exception).
5. **Replace the settings screenshot with a crop.** Crop `window-settings.png` to the General card (Length / How Often / the three keys) at 2× for about 520 px wide, or draw the four privacy facts as a small HTML card in the window's style. At ≤600, hide the image.
6. FAQ link: drop `margin-left` and `display:inline-block` from `.faq dd a` and put it after a space, so it stays on the answer's line.

## 2. Brand: 8

Good: reads as the app at a glance. The cream, the frosted white field with `tab` keycap, model pill and power button, the glass gradient on the second hero line and on every suggestion, the mark in the nav and the icon at the close. Instrument Serif is used only for display, as the playbook says. Against Wispr Flow/Dia it holds up.

Holding it back:
- The hero ribbon text is SF at 19 px, set on a curve. It is the largest block of moving body type on the page, and on a curve SF looks like a WordArt effect rather than the arch from the icon.
- The windows in sections 2 and 3 have traffic lights and grey bars: generic Mac mockups, not the app's language. Only the suggestions tie them to the brand.
- The glass gradient is spread thin: on suggestions at 15–17 px the gradient is barely visible and reads as light blue text.

Changes:
1. **Hero ribbon:** make the ribbon itself the brand object. Keep the blurred arch stroke, and either take the text off it entirely (see Motion 1) or set it smaller (15 px) at about 60% ink opacity, so the arch dominates and the text is texture, not content.
2. **One stronger glass moment per section,** at a size where the gradient shows: suggestions at 19 px or more in sections 2 and 4 (the playbook's own D at a large size shows it).

## 3. Message: 7

Good: the headline + eyebrow + lead tell you within 5 s what it is, that it is a Mac app and how to get it. The download is above the fold at every width. The lead is 17 words.

Holding it back:
- **The hero's proof is cut by the fold.** At 1440×900 the field's bottom bar sits at y≈882–915: the `tab` key, model pill and power button are half off the first screen. At 1024×900 too. The field is where the product is shown; it should be whole.
- **The same three sentences five times.** "Happy birthday! I hope you have a great day!", "Thanks for the update…", "Running 10 minutes late…" appear in the ribbon, the hero field, section 2, section 3 and section 4. By section 3 a visitor has read each one at least three times. Sections 2–4 add no new information about what it can do.
- **Section names don't match.** The nav says "FAQ", the section says "Limits.", and the list is mostly not limits ("What does it cost?").
- "The smallest download." is fine, but its subtitle "And light when you're not typing." is the actual differentiator; Wispr/Linear would make the at-rest number the headline.

Changes:
1. **Raise the hero so the field is whole at 900 px.** `.hero` padding-top 64 → 32, `.hero__stage` height 400 → 340, `.hero__field` bottom 48 → 32, `.lead` margin-bottom 32 → 24. Check that the field's bottom edge is ≤ 860 at 1440×900 and 1024×900.
2. **Give sections 2–4 their own lines.** Rule 3 binds the *demo* (`runDemo`) to the README's messages; the static still shots in sections 3 and 4 can use other ordinary, invented, clearly non-private sentences (for example "Can we move the call to Thursday afternoon?", "The slides are in the shared folder."). If John wants only README lines, then at least don't run `runDemo` in both the hero field and section 2: show one message per window there, each different.
3. **Rename section 8 to "Questions."** (or the nav to "Limits"), and keep the nav label and the heading the same.
4. Compare heading: consider "Small download. Light at rest." so both claims sit in the headline, with no subtitle.

## 4. Motion: 6 (under the bar)

Good: the Korean animation is excellent: Tab presses, each jamo key lights as the IME composes, the glint lands on 습니다. One motion, about every 7 s, says exactly what the section claims. Reduced motion shows clean finished states (checked: hero field, section 2 window title "Team Chat", Korean field, no ribbon motion). No scroll-jacking, no layout shift seen.

Holding it back:
- **Two motions in the hero, on the same text.** The ribbon scrolls the three sentences continuously (linear `<animate>` on `startOffset`, 48 s) while the field below types the same sentences with `runDemo`. Two things moving, saying the same words, at different speeds. The checklist allows one signature motion per section.
- **The ribbon text goes under and into the field.** At 1440 the words ("hope you have…") slide under the field's top edge and disappear; at 1024 "I'll take a look and get back to you" runs straight into the field's bottom-right corner; at 390/320 it dives behind the field. It looks like a collision, not a design.
- **Linear easing.** The ribbon is a constant marquee (`calcMode` linear by default). The checklist asks for easing.
- **Section 2 runs a second copy of the hero demo** at the same time. It also loops all three messages, so it repeats the hero exactly.
- Section 3 and 4 are still. That is fine, but with the previous point the page has two copies of one motion and then nothing new until Korean.

Changes:
1. **Pick one hero motion.** Recommended: keep `runDemo` in the field (that's the product) and make the ribbon still: the three messages set once along the arch at about 60% ink, the glass parts in the gradient, no `<animate>`. Or, if the ribbon must move, make it move in steps: on each `onMessage` from the hero's `runDemo`, slide the ribbon so the current message is centred, over 1.2 s with `cubic-bezier(.2,.7,.2,1)`, so the two motions are one.
2. **Keep the ribbon text off the field.** Change the `#rp` path so its lowest point stays at least 32 px above `.hero__field`'s top at every width, or clip the text with a mask that fades it out 24 px before the field (an SVG `mask` with a gradient rect). Check at 1024 and 390, where it collides today.
3. **Section 2: one key, one moment.** Instead of a second full `runDemo`, loop a single 6 s beat: type "Running 10 minutes late, sorry! Sa", the suggestion appears, the big Tab key presses, the glint runs over "ve", then Shift-Tab takes the rest. Start it when the section enters the viewport (`IntersectionObserver`) and pause it off-screen; today both demos run all the time.
4. Pause the hero `runDemo` and the Korean loop when off-screen (same observer). It saves CPU on a page whose pitch is "light at rest".

## 5. Honesty: 7

I checked every number and claim against `README.md` and `docs/site/compare/README.md` (and a2's `#cost`):
- Compare figures: 0.53 / 1.27 / 2.98 / 3.85 GB; 79 / 185 / 383 MB (478 MB in a first run); 0.2 / 0.2 / 2.2% (Halftype 0.13–0.27% over 60 s, Cotypist median with a 13% sample, Cotabby median of 9); the Korean row; the how-measured paragraph with KeyType left out at rest and why. **All match.** The bar widths are proportional.
- Privacy rows: one permission, no Screen Recording; Hugging Face + SHA-256 + daily update check; settings, models and four counts a day, no text, no logs; secure fields skipped. **Match** README §Privacy.
- FAQ: "about a fifth of keystrokes in English" (README: 21.6%) with the measuring link; macOS 26 / Apple Silicon; "Mid-line, in password fields, and during Secure Input" (README Limits); MIT, free; Korean answer. **Match.**
- The playbook rules on install (DMG URL, brew line, copy copies both lines) hold.

Problems:
- **The mobile Korean table drops the qualification column.** `@media (max-width:760px) { .ko-table td:last-child { display:none } }` hides "Measured: 0.69 keys saved per mid-syllable request", "Apple offers inline predictions in English, French and Spanish", "No completion through a composing syllable in their source" and "Closed source". At 390/320 the table says "Cotabby, KeyType: Not found" with no "in their source": that's a stronger claim than the README makes. Rule 7: don't drop a qualification.
- **"Chromium apps? Mostly. Only some are tested."** README line 99: Korean was used in T3 Code (one Chromium app) and works; *other Chromium apps haven't been run yet*. "Mostly" claims a result nobody has measured.
- **"Halftype 0.2%" CPU bar**: a rounded midpoint of 0.13–0.27%, which a2 also uses and the note qualifies. Acceptable, flagged only so nobody removes the note.
- NOTES.md says a2 has "478 MB in a second run". It doesn't: a2 says "in a first run", like compare/README.md and this page. There is no discrepancy; correct the note.

Changes:
1. **Keep the qualification on mobile.** Delete `.ko-table td:last-child { display:none }`. At ≤760 make each row a block: `th` and the verdict on one line, the qualification on the next at 13 px muted (`.ko-table tr { display:grid; grid-template-columns:1fr auto } .ko-table td:last-child { grid-column:1/-1 }`).
2. **Chromium answer from the README:** "Used in T3 Code. Others aren't tested yet." (or drop the question).
3. Correct NOTES.md's "second run" line.

## 6. Responsive / solid: 7

Good: no console errors, no sideways scroll at 1440/1024/768/390/320, nav collapses to logo + Download, the install block wraps cleanly, charts stack to one column, focus ring defined (`:focus-visible`), alt text and `role=img` labels on every demo, `lang="ko"` on Korean.

Holding it back:
- Ribbon collisions at 1024 and 390/320 (see Motion 2).
- Hero field half below the fold at 1440×900 and 1024×900 (see Message 1).
- At 390 the stacked section 3 windows have tube fragments leaking at both edges.
- Glass suggestion text is below AA (light blue/grey on white, about 2.5:1). NOTES calls it decorative, but at 15–17 px in sections 3–4 it's the content a reader is meant to read. The `role=img` labels cover screen readers, not low-vision sighted readers.
- The `.section--soft` beige bands (Korean, Compare) start and stop with hard edges; at 390 they make the page look striped.
- I couldn't check Safari's `backdrop-filter`/`textPath`, or the clipboard permission.

Changes:
1. Fix the ribbon (Motion 2) and fold (Message 1), and recheck at 1024×768 and 390×844.
2. Hide `.tube` at ≤960 (Polish 1).
3. Darken the glass gradient for text only, keeping the hue: for example `#3f7fc4 → #7c8fa6 → #c9673a` on `.ghost`, which gets close to 4.5:1 on white at the ends; keep the lighter gradient for the big serif line.
4. Fade `.section--soft` in and out with a 64 px `linear-gradient` at its top and bottom, or use the cream throughout and separate sections with spacing only (Linear, Things).

---

## Top changes for round 2, in order
1. **Hero:** one motion only (still ribbon or ribbon stepped with `onMessage`), ribbon text kept clear of the field, field whole above the fold at 900 px. (Motion, Message, Responsive)
2. **Mobile Korean table:** show the qualification column; "Chromium apps" answer from README line 99. (Honesty)
3. **Section 3 tube:** a blurred arch running off the edges, not a capped neon pipe; hidden when the windows stack. (Polish, Brand)
4. **Stop repeating the demo:** section 2 a single 6 s Tab/Shift-Tab beat started on view, sections 3–4 with their own lines or one message each. (Message, Motion)
5. **Section 2 and Three keys craft:** a filled Mail/Messages window with the keycap placed deliberately; key cards that show before → after with the label inside. Then collapse the type scale to 4 sizes. (Polish)
