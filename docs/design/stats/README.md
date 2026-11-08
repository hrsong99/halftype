# The Stats page, upgraded (round 1)

Question: how should the Stats page look, borrowing from Divan Raj's sleep dashboard (`~/Desktop/Synced/links/2026-11-08-desdivj-sleep-dashboard-dataviz.md`)?
John: "create a thread that upgrades the stats page and shows me /variants". The link note asked for, in order: hover a bar for that day; a "+12 vs yesterday" delta; a Day / Week / Month switch once there are months of data; no stacked colour bars.

Found: hover already ships (`chartXSelection` changes the caption). There are no hourly counts, so no Day view.

- `index.html`: A today, B delta + tooltip at the bar, C share of typing by Tab as the hero (bars coloured by personal model on/off), D halftone dot calendar, E Week / Month / All, F one sentence. G and H are Codex image ideas. Bars are hoverable, E's switch works.
- `options.png`: frozen screenshot of the page.
- `sample-tally.json` (from `make-sample.py`): Nov 8 is this Mac's real `stats.json` (counts only); the 13 days before are made up.
- `images/today.png`: today's page, from `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots/stats` (run on 2026-11-08: the chart ends on the day it runs; the sky is blank off screen). `icon.png` and `today.png` were passed to Codex; `G.png`, `H.png` and `prompts/`.

Recommendation: C with B's tooltip. Pick: (pending)
