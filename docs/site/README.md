# Landing-page drafts (round 1, 2026-11-08)

The question: which direction for Halftype's first landing page? John: "why don't you try making a landing page or two for our app (it's called halftype now)". Nothing is deployed, and the GitHub homepage field still points at the releases. That is John's call once he picks one.

- `index.html`: the variants page. It shows A and B live side by side, plus image ideas C and D. Shared at https://share.hrsong99.xyz/o01ct9f75y5orO6q/ (unlisted, noindex; remove it with `ssh js rm -r share-site/html/o01ct9f75y5orO6q`).
- `a/`: "Sky", a light page. The hero is the Halftype field over a canvas copy of the app's halftone sky (`Sky.metal`).
- `b/`: "Ink", a dark page. The headline completes itself with Tab.
- `ideas/`: C (a Korean risograph poster) and D (the whole Mac as the hero), from Codex's image tool. `gen.sh` and the `*.prompt.txt` files made them. Their copy is the image model's, and some of it is wrong.
- `shots/`: frozen full-page screenshots of A and B at 1440 and 390 px wide.

How A and B were made: each by one agent with TasteSkill's `design-taste-frontend` skill ([leonxlnx/taste-skill](https://github.com/leonxlnx/taste-skill) at `f6b7657`, from a scratch clone, never installed). The agents ran its deal scripts and its checker and gate, three rounds at most. Each folder's `.taste-skill/` (gate state, waivers) and `shots/` are gitignored. The kit files the pages load are copied into each `assets/`, under MIT.

Both pages replay the six suggestions in `docs/media/{en,ko}.gif`, which `scripts/demo.sh` drew from the real model and gate. Korean is typed key by key, as 2-set composes it. No other ghost text is invented. Each page says the sentences are ones the model does well on, which overrides the skill's no-caption rule. Every fact comes from the README. A README change that touches a privacy claim or a number must change these pages too, until one of them replaces the other.

Preview locally: `python3 -m http.server -d docs/site` and open `http://127.0.0.1:8000/`.

## Round 2 (2026-11-09)

John: "A looks best but it has some overly long ux writing and i want to see a version of the "resource" section comparing it to incuments, showing graphically/visually why we're much better".

- `round2.html`: A2 next to A.
- `a2/`: A with every section's copy cut, and the Cost section rebuilt as two bar charts against Cotypist. The method is in `docs/measuring.md`, "Against Cotypist".
- Copy rule for these pages, from that feedback: a hero lead of 20 words or fewer, a card title with no sentence under it, an FAQ answer in one short line. Detail goes to the README.

## Round 3 (2026-11-09)

John: "no need to only mention cotypist, i think there are a few incumbents no? And are there other metrics that measure speed and accuracy and resource use? I do like A2 more though". He agreed to: macOS predictions, Cotypist, Cotabby, KeyType, with Grammarly as a privacy row; and to showing every result, losses included.

- `round3.html`: A2's comparison, full width.
- `compare/`: the measurements, their method and `idle.sh`.

Round 3 fix: KeyType's at-rest bars were removed. It had been measured switched off (no Accessibility); see compare/README.md.

## Polish (2026-11-09)

A2 went through TasteSkill's gate: OPEN 3 after 3 rounds. Still open: the model pill counts as a second button style (it copies the app's own UI), the comparison charts' row lines at 1440, and one Korean line flush at 390. Waivers are in `a2/.taste-skill/waivers.json` (not committed): key-card titles, the kit nav at 320, charts as the section's visual, the FAQ without a picture, and the airy statement section.
Codex reviewed A2 and `compare/idle.sh` over four rounds until clean. It found a Korean replay that showed impossible states (하ㄹ where 2-Set shows 할), savings figures without their limits, the Korean memory line missing its 270 MB footprint, rival qualifications, canvas resizing, a pause button inside `role=img`, tooltips that clipped, and `idle.sh` leaving an app running when interrupted. All fixed.

## Round 4 (2026-11-09)

John: "We should probably cut down on so much of the korean stuff, our first audience will be english. But overall doesn't look bad as a start, obviously need to update it to match the newer app."
- A2 is English-first: the Korean summary section is gone; the replay is three English lines and one Korean; the keys use English examples; the statement shows English figures (21.6% saved, 81.5% first word right, 53 ms); the one Korean section and one Korean FAQ answer stay.
- Matched to main after the merge: network (the daily update check stays on; Update Automatically only stops the download), on-disk (four counts a day for Stats), and main's General screenshot.
- Domains on Spaceship, 2026-11-09: halftype.app $8.28 the first year, then $14.49 a year; halftype.dev $8.28, then $12.42. halftype.com is taken.

## Pick

A over B (round 1). A2 over A (round 3).
