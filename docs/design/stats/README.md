# The Stats page, upgraded (round 1)

Question: how should the Stats page look, borrowing from Divan Raj's sleep dashboard (`~/Desktop/Synced/links/2026-11-08-desdivj-sleep-dashboard-dataviz.md`)?
John: "create a thread that upgrades the stats page and shows me /variants". The link note asked for, in order: hover a bar for that day; a "+12 vs yesterday" delta; a Day / Week / Month switch once there are months of data; no stacked colour bars.

Found: hover already ships (`chartXSelection` changes the caption). There are no hourly counts, so no Day view.

- `index.html`: A today, B delta + tooltip at the bar, C share of typing by Tab as the hero (bars coloured by personal model on/off), D halftone dot calendar, E Week / Month / All, F one sentence. G and H are Codex image ideas. Bars are hoverable, E's switch works.
- `options.png`: frozen screenshot of the page.
- `sample-tally.json` (from `make-sample.py`): Nov 8 is this Mac's real `stats.json` (counts only); the 13 days before are made up.
- `images/today.png`: today's page, from `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots/stats` (run on 2026-11-08: the chart ends on the day it runs; the sky is blank off screen). `icon.png` and `today.png` were passed to Codex; `G.png`, `H.png` and `prompts/`.

Recommendation: C with B's tooltip. Pick: none outright; John asked for round 2.

## Round 2: past weeks, a halftone calendar, and icons

John: "I guess today's page is okay, but adding a halftone calendar could be nice; adding week/month/all, or A with a way to see past weeks, might help? and i'm wondering if we should add these icons. Show me a version with that all in mind (and look at main to see our updated designs)". The icons are the SF Symbols in Codex's image G.

- `round2.html`: drawn on main's window (cream, the floating sidebar card, one scroll). A main today; B Week / Month / All, with ‹ › paging back and All as the halftone calendar; C today with ‹ › on the 14 days and the calendar below. Then three sidebars: 1 today (peach dot), 2 icons and the dot, 3 icons with the current one in peach. A switch above shows the sample or the real two days. `round2.html?all`, `?month` and `?real` open B on All, on Month, or with the real data, for screenshots.
- `round2.png`: frozen screenshot.
- `sample-tally-2.json` (from `make-sample2.py`): 16 made-up weeks, with Nov 8–9 from `real-2days.json`, this Mac's `stats.json` on 2026-11-09 (counts only).

Recommendation: B with sidebar 3. Pick: (pending)
