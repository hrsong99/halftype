# H, hand-built (rounds 1–3; round-1 Decisions below are superseded by the Round 2 and 3 sections)

Files: `index.html`, `page.css` (own CSS, ~200 lines), `page.js`, plus copies of `base.css`, `demo.js`, `arch.svg`, `icon.png`, `models.png`. `shots/check.mjs` makes the shots and the checks below. No kit, no framework, no scripts from a CDN; Instrument Serif comes from Google Fonts.

## Decisions
- Hero is option C: serif headline with its second line in glass, and the demo's three messages flowing along the arch (`textPath`, 48 s seamless loop, measured in JS). The frosted field below runs `runDemo`. The lead is 17 words.
- "Right where you type" is option D. One window runs `runDemo` with a big Tab keycap, and its title and header change per message (Messages → New Message → Team Chat) through `onMessage`, so nothing shifts.
- "In almost every app" is image J built in HTML: three windows at different depths, joined by an SVG glass tube. It uses the README demo's lines instead of J's invented ones. It is still (no caret blink); below 960 px the windows stack.
- Three keys are still cards (Esc shows the suggestion struck through).
- The Korean animation is the one motion in its section, every ~7 s: Tab presses, then each jamo key lights up as the IME composes it (반값 → 반갑스 → … → 반갑습니다.), ending in the glint.
- In Compare, each chart's hover tooltip from a2 is a visible note, so no qualification hides behind hover.
- Reduced motion: still states, no ribbon motion, no caret blink.

## Would still change
- The tube in section 3 could look more like glass (a refraction highlight).
- Glass suggestion text is below AA contrast. It is decorative, and every demo has role=img with a full label.
- No dark mode. The app is cream only.

## Couldn't check
- Real Safari rendering of backdrop-filter and SVG textPath. Only headless Chromium was used.
- The copy button with real clipboard permission.

## Shared-file discrepancy (round 1, corrected)
- Round 1 said a2 had "478 MB in a second run". a2 says "first run", like compare/README.md and this page; it was fixed in ab34d98.

## Round 2

Changed, most impactful first:
1. **Hero, one motion.** The ribbon is still (no `<animate>`) and carries its own six invented lines at 15 px, 55% ink, in a 150 px band (120 at ≤600) that ends 24 px above the field at every width (measured). The field below it is the only motion. Field bottom at 1440×900: 837; at 1024×900: 785.
2. **Honesty.** Korean table reflows on phones (verdict beside the name, qualification under it) instead of hiding the column. Chromium answer from README line 99: "Used by hand in T3 Code. Others aren't tested yet." Added the 21.6% / 81.5% / 53 ms strip under Compare, each with its own qualification (21.6% with real typing delays before the latest length change; 81.5% over 2,400 held-out requests; 53 ms median of requests that reached a first word) and the measuring link.
3. **No repeated sentences.** The README demo runs only in the hero field. Section 2 is a ~7 s Mail-reply beat with its own line (type "Can we move it to Th", Tab takes "ursday" with the glint, Shift-Tab takes " afternoon? I have a clash at ten."), started on view. Section 3 (Messages, Notes, Team Chat) and the key cards each use their own invented lines.
4. **Section 3's tube** is one wide blurred arch stroke (.6) plus a blurred 2 px highlight, both ends off the container, no caps; below 960 it is hidden and one `.arch` sits behind the stack. The section clips sideways only (`overflow-x: clip`), so the blur doesn't end in a hard line.
5. **Section 2 window filled:** To and Subject rows, the typed line, a quoted earlier message; the big key overlaps the window's bottom edge by half, centred.
6. **Key cards** show before, the key, after, with the title inside the card; taken letters get a 2 px glass underline; Esc's "after" shows the caret alone and "The next Esc goes to the app" (README).
7. **Pause and off-screen (rule 16, from K).** One 44 px pause control in the sticky nav, so it's visible everywhere; it holds all three demos (a gate in my `demo.js` copy's `wait`) and every CSS animation (`html.held`). Each demo also waits while off screen (IntersectionObserver). Checked headless: paused hero text doesn't change; the Mail beat is idle off screen and runs on screen. Hidden under reduced motion.
8. **Type: 5 sizes** (13, 15, 19, h2 clamp, display clamp), counted over every visible text node at each width. Demo text is 19 everywhere it's the subject (hero, Mail, keys, Korean); body/UI 15; notes/mono 13. `code, kbd, pre` set to the mono stack: no Courier.
9. **Spacing:** sections 64 px top and bottom (128 between at 1440); the soft beige bands are gone (cream throughout, spacing separates).
10. **Privacy image** is a crop of the Models card (`models.png`, 1056×664, shown ≤528 px, "They run on this Mac"), hidden at ≤600. `window-settings.png` removed from this folder.
11. Small: nav and heading both "Questions"; FAQ link stays on its line; Compare heading "Small download. Light at rest." with no subtitle; chart values `nowrap`; suggestion text in small windows wraps by word.
12. Close: the app icon was already there (K's other borrowing); its arch is already behind the content.

Not taken, and why:
- **Darker glass for suggestion text** (Responsive 3): rule 1 fixes the gradient to the app's colours, and the app draws suggestions in exactly these. Instead suggestions are 19 px wherever they are the point, and every demo has a role=img label. Still below AA for sighted low-vision readers; John's call.
- **Ribbon stepped to the field's message** (Motion 1 alt.): rule 10 says the ribbon must not show the field's sentence at the same time; still is simpler.
- **Ribbon text removed entirely:** kept as texture, since the arch with text is what John picked in C.
- **Sections 2–3 cycling Mail → Messages → chat:** one beat per section (rule 11).
- **Dark mode:** the app is cream only.

Would still change: the ⇧ glyph is small in SF Mono keycaps; section 3 leaves the top-right corner empty at 1440.

Checked (headless Chromium, 1440 first/full/reduced, 1024, 768, 390, 320): zero console errors, no sideways overflow, 5 text sizes at every width, no Courier, ribbon-to-field gap 24 px everywhere, controls ≥44 px with their hit areas (nav Download 36 + 4 px `::after` each side, Copy 28 + 8 px). Not checked: Safari, the real clipboard, a keyboard-only walk.

## Round 3

Changed, most impactful first:
1. **Section 3 windows hold real invented content (rule 18).** Sidebars are lists (Sam / Alex / Jo; Weekend / Groceries / Trip; # general / # web / # design) and the bubbles say "Game starts at 7?" and "Yes! Section B". Team Chat has one earlier message ("Mina: The login page breaks on Safari again."). No grey bars are left. On phones the sidebar sizes to its labels, so nothing is cut off with an ellipsis.
2. **Pause is hidden under reduced motion** (`.pause[hidden] { display: none }`). Measured: `display: none` in reduced-1440 and `grid` everywhere else.
3. **Phones.** The 4.35em min-height applies only to the hero field, so the Korean card fits its line. The jamo row stays on one line (8 equal keys, 4 px gap). The fine print has "Updates&nbsp;itself". At ≤600 the footer is a column: the logo, then the links in a 2×2 grid. `text-wrap: pretty` on answers and notes ("no logs." no longer orphans).
4. **The close.** 96 px top and 128 bottom, and the FAQ's bottom padding is 48, so the last FAQ row sits about 150 px above the icon. The arch is 520 px tall from 20%, with a radial mask, so it fades out on every side with no hard edge at the footer or the sides. A linear mask left the blur's box edges visible.
5. **Key cards press once in view.** Each card in turn presses its key (180 ms) and then shows its after state, using the hero's `.taken` glint, not the old underline. It plays once, respects pause and off-screen, and under reduced motion the markup's finished states show with the glint's end frame.
6. **The ⇧ glyph is drawn in SF at 15 px (19 in the big key),** next to "tab" (SF Mono's ⇧ was half the cap height). It is a shared `SHIFT_TAB` in my demo.js copy. Keycaps use `grid-auto-flow: column` so the glyph sits on the same line.
7. **Honesty.** Cotypist: "one 13% sample in each of two 8-minute runs" (compare/README). The Korean row now reads "0.69 keys saved per mid-syllable request, with more wrong suggestions (18.2% against 8.4%)" (rule 17). The chart note says "Gemma 4 E2B Q4_C", so it doesn't clash with the screenshot's 3.4 GB.
8. **The hero ribbon drifts.** Six more invented lines make it longer than the arch, and its `startOffset` eases from one end to the other over 60 s and back (cosine). It runs only on screen and stops on pause. Under reduced motion it stays still. No sentence repeats, and the ribbon's lines never match the field's.
9. **The Mail stage has no box.** The window sits on the blurred arch on cream, like section 3.
10. **Small.** A skip link (visible on focus). The eyebrow reads "· English and Korean". The footer mark is 22 px. The figures' "How it's measured" is a 44 px `.more` link. The hero field holds each finished message for 2.6 s (it was 1.6), so it is rarely empty.

Checked (headless Chromium at 1440, 1440 reduced, 1024, 768, 390 and 320): 0 console errors; scrollWidth equals the viewport at every width; 5 text sizes at every width (13, 15, 19, h2, display).

Not taken:
- **The glass suggestion text's AA contrast** (about 2.2:1 for `#99b0c9` on white). It is the app's own look (rule 1), at 19 px, and each demo has a full `role=img` label. **John's call:** keep it, or darken the middle stop on the page only.
- **`models.png`'s small bitmap text.** Drawing the Models card in HTML would add a lot of markup to one section. It stays a picture, hidden at ≤600, where the privacy rows carry the claims.

Couldn't check: Safari (backdrop-filter, `textPath` drift, mask-image), the real clipboard, a screen reader pass.

## Fix round (Codex review, review-r3 small items)

1. **Glass text contrast, page only** (the app keeps its own colours). Each stop is the app's stop scaled toward black, keeping its hue, until it is at least 4.5:1 on cream (the darker of the two backgrounds, so it is the worst case):

   | Stop | App | Page | On cream #f6f1e9 | On the frosted field (~#fbf9f6) | On white |
   |---|---|---|---|---|---|
   | blue | #5f9bd8 (2.61) | #45709d | 4.60 | 4.92 | 5.18 |
   | grey | #99b0c9 (1.99) | #606e7e | 4.64 | 4.96 | 5.21 |
   | peach | #e88f5e (2.19) | #995e3e | 4.64 | 4.96 | 5.22 |

   The same three stops are used for `.ghost` (base.css), the glint's band (`.taken`, which was #73a6e0/#c2d4e8/#ed9a6b, 1.35–2.26:1), `--glass` (the headline's glass line, the close, 21.6%) and the ribbon's `#gl`. Blends between two stops are darker than either in linear light, so the whole gradient stays above 4.5. The Compare bar for Halftype is not text and keeps the app's light stops.
2. **Reduced motion can change after load.** `Motion.held` is now the pause control or reduced motion. A `change` listener on the media query runs `update()`, which shows the still finished states (the hero sentence, the Mail and Korean lines as in the markup, every key card's after state), stops the caret blink and glint (`html.reduced`), stops the ribbon and hides the pause control. Switching it off brings the demos back and shows the pause control, including on a page loaded with reduced motion on.
3. **Key cards trigger one by one.** Each card has its own observer entry. Cards on one row (desktop) take turns 880 ms apart; stacked cards (phones) each play when they scroll in.
4. **Off screen and paused.** The ribbon's `requestAnimationFrame` loop exits when paused, reduced or off screen, and `ribbonRun()` restarts it from the observer and the pause control. Every observed demo gets `.off` off screen, which pauses its CSS animations (caret blink, glint).
5. **Clipboard failure** inserts both commands under the line as a selectable, pre-selected `<pre class="brew-lines">` and the button reads "Select below" (`shots/clipboard-fallback.jpg`).
6. Small: `SHA&#8209;256`, `8&#8209;minute` (non-breaking hyphens). FAQ columns 1fr 2fr, so every answer is one line at 1440, 1024 and 768; the "How it's measured" link is nowrap and 44 px tall. The Esc card's hint is its own line under the field, shown with the after state. Section 2: no top padding on the stage (48 px from the subhead to the window) and the body's text holds one line at ≥760 (two on phones, where it wraps). Section 3: Notes is 60 px higher at 1440, and at ≤960 the stack is 640 px wide and centred (64–704 at 768), like the keys and charts.

Not changed: the second "How it's measured" link in Compare (review-r3 item 6, not in this round's list).

Checked with `shots/check.mjs` (headless Chromium at 1440, 1440 reduced, 1024, 768, 390 and 320, scrolled through): 0 console or page errors; scrollWidth equals the viewport at every width; 5 text sizes at every width (13, 15, 19, h2, display); FAQ rows 23 px (one line) except the 44 px link row at ≥768. Runtime toggle with `page.emulateMedia`: the hero text and ribbon move before, stand still for 2.5 s after switching to reduce (caret animation `none`, pause hidden), the Mail beat stays still on screen, and both resume with the pause shown when switched back; a page loaded reduced starts moving when switched off; paused, the hero and ribbon don't change. Not checked: Safari, a real clipboard denial, a screen reader.
