# Review, round 3 (fresh reviewer)

Read PLAYBOOK.md, the references (Raycast, Linear, Wispr, Dia, Things, Cursor, CleanShot), README.md and docs/site/compare/README.md (and its `*-idle.txt`), then scored `index.html` before reading NOTES.md or earlier reviews. Served `docs/design/landing-polish` over http and shot it with the cached headless Chromium: 1440×900 first screen at 0.3/2.5/5/8/12/18 s, the Mail beat at 0.6/2.2/3.2/4.6/7 s, every section at 1440, full page, reduced motion (first screen and full), then 1024, 768, 390 and 320 (first screen, full page, each section at 320 and 768, the 320 footer).

Measured: 0 console errors and 0 failed requests at every width; `scrollWidth` equals the viewport at every width (only the blurred `.arch` boxes extend, clipped); 5 text sizes at 1440 (13, 15, 19, 56, 92); `code`/`kbd` in SF Mono, no Courier; small visible controls (nav Download 36 px, Copy 28 px) get 44 px hit areas from `::after`; page weight 324 KB without `shots/`.

## Scores

| Area | Score | Why |
|---|---|---|
| Polish (craft) | **8** | Tokens, radii (20 field, 14 windows, pills), one container and a quiet type scale hold everywhere; the section 3 windows now carry real labels and look like Mac windows. Still short of Linear/Raycast in a few visible spots: "SHA-\n256" breaks at its hyphen, FAQ answers wrap mid-link, the Esc card's hint reads as part of the sentence, and the Mail stage has ~80 px of dead cream above the window. |
| Brand | **9** | Cream, ink, the blurred arch, the frosted field with the Qwen pill and power button, glass suggestions, the glint, the icon in the close. It is the app window, enlarged. |
| Message | **9** | At 1440 and 1024, in one screen: what it does (headline + live field), Mac (eyebrow, button), how to get it (Download + brew). The lead is 18 words. |
| Motion | **8** | Each section has one motion, started on view, held by one pause control; key cards press once; the Korean beat composes jamo correctly (반갑 → 반값 → 반갑스 → … 반갑습니다.); the ribbon's 60 s cosine drift is calm and never shows the field's sentence. Reduced motion shows finished states and hides the pause. The ribbon drift plus a typing field plus the Mail beat a scroll later is a little busy for "one signature motion", but each stays in its section. |
| Honesty | **9** | Every number matches README.md / compare/README.md: 0.53/1.27/2.98/3.85 GB, 79/185/383 MB (478 MB first run), 0.2/0.2/2.2% (Cotabby median of 9 checked against `cotabby-idle.txt`), 0.13–0.27%, 0.69 keys with 18.2% vs 8.4% wrong, 21.6% / 81.5% / 53 ms with their qualifications, T3 Code only, the KeyType at-rest exclusion. Nothing invented; the demo carries no disclaimer. |
| Responsive / solid | **8** | No overflow or overlap at 1024/768/390/320; 320 footer is a tidy logo + 2×2 links; jamo row fits on one line; qualifications reflow rather than hide. Docked for: glass suggestion text below AA (inherent to the brand; labelled by `role=img`), and at 768 the stacked windows in section 3 run to 24 px from the edge while everything else sits on the container. |

**Average 8.5, nothing under 8. Meets the bar.**

## Remaining changes, most impactful first

1. **"SHA-256" breaks at the hyphen** (Privacy, `index.html:157`, visible at 1440: "SHA-" / "256 checked"). Use `SHA&#8209;256` (non-breaking hyphen) or wrap it in `<span style="white-space:nowrap">`. Same check for "8-minute" in the CPU note ("8-" / "minute runs" at 1440): `8&#8209;minute`.
2. **FAQ answers break mid-link and over two lines** at 1440 (`.faq dd`): "About a fifth of keystrokes in English. How / it's measured" and "Mid-line, in password fields, and during / Secure Input." Rule 4 wants one line. Let the dd use the column's full width (the T3 Code answer proves it fits) and give the link `white-space: nowrap`; or drop `text-wrap: pretty` from `.faq dd`, which is what pulls words down.
3. **Esc card's after state** (`.key:nth-child(3) .hint`): "Back in fi| The next Esc goes to the app" reads like one garbled sentence. Put the hint under the field as a caption (`display:block`, muted, 13 px), or replace with "Back in fi|" alone and move "The next Esc goes to the app" to the card title's one short line.
4. **Dead air around the Mail window** (section 2 `.stage`): ~80 px between the subhead and the window at 1440 and ~100 px at 320, then a tall empty body between the sentence and the quote. Tighten the stage's top padding to 32–40 px and the body's min-height so the window reads as a compose window, not a padded box.
5. **Section 3 at 768**: Messages starts at x=24 and Notes ends at x=744, outside the 1440 container rhythm everywhere else; the right of the 1440 layout also has an empty quadrant above Notes. Keep the windows within the container at 768, and at 1440 nudge Notes up ~60 px so the three read as one cluster around the tube.
6. **Two "How it's measured" links** in Compare (end of the `.how` paragraph and the `.more` under the figures), both to `docs/measuring.md`. Keep the `.more` one; end the paragraph without a link.
7. **Glass text contrast** (~2.2:1 for the middle stop): John's call, as NOTES says. If kept, it's brand-justified; the `role=img` labels cover screen readers.
8. **NOTES.md is slightly stale**: its file list names `window-settings.png`; the folder has `models.png`.

## Round 3 claims in NOTES.md

| Claim | Landed? |
|---|---|
| 1. Section 3 windows hold real invented content, no grey bars | Yes. Sidebars, bubbles, a Mina message; no skeleton bars at any width. |
| 2. Pause hidden under reduced motion | Yes. Absent in the reduced 1440 shot. |
| 3. Phones: Korean card fits, jamo one line, "Updates itself" together, footer column with 2×2 links | Yes at 390 and 320. "no logs." no longer orphans. |
| 4. Close: tighter padding, radial-masked arch | Yes. No hard edge at the footer or sides; the FAQ → icon gap is reasonable. |
| 5. Key cards press once in view with the glint | Yes. |
| 6. ⇧ in SF beside "tab" on one line | Yes, in the card and the big key. |
| 7. Honesty edits (Cotypist CPU, Korean cost, Q4_C) | Yes, all three, and they match the sources. |
| 8. Ribbon drifts 60 s eased, own lines, still under reduced motion | Yes. Positions differ across the 0.3–18 s shots; never the field's sentence. |
| 9. Mail stage has no box | Yes. |
| 10. Skip link, eyebrow, 22 px footer mark, 44 px `.more`, 2.6 s hold | Yes (skip link in markup; `.more` 41 px tall measured, with padding close to 44). |

Not checked: Safari (backdrop-filter, textPath drift, mask-image), the real clipboard, a screen reader.
