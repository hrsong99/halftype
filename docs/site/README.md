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

## Pick

(not yet)
