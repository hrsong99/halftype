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

Recommendation: B with sidebar 3. Pick: B with sidebar 3 (John: "sure go ahead with your suggestion"), built on the branch `stats-variants`. `built/` holds the shipped page on Week, Month and All, from `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots/stats` (a real window behind everything; run it on or soon after 2026-11-09). Built differences: the week starts where the user's calendar starts it, and the change sits beside each label, not the number, so it fits the smallest window.

## Round 3: show the value

John: "I think the stats page needs an upgrade to directly show our value. I think we should make it more understandable and intuitive how many tabs they've accepted and letters/words got accepted, along with how much time they saved and stuff. What are the main stats that are most important you think?"

All in `round3/`, on this Mac's real week so far (Nov 9–10, counts only). The window is drawn taller than 720×500 so the whole page fits.
- `index.html`: A today (Tabs first); B time saved first; C "1 in 8" as a 10×10 grid of keys; D one sentence; E four tiles with sparks; F the sum (Tabs × letters each = words ≈ minutes). G, H, I are Codex images (`I.png`, `J.png`, `K.png`, from `gen.sh` and `prompts/`): a filling ring, a keycap strip, a shareable weekly card.
- `options.png`: frozen screenshot.

Ranking proposed: time saved, words (letters ÷ 5), share as "1 in every N keys", Tabs last; leave out taken ÷ shown. Time assumes 40 wpm in the mockups; the build should measure typing seconds per day instead.

Recommendation: B with C's "1 in every 8 keys" label. Pick: pending.

## Round 4: one short sentence, and G's bars

John: "What about D's writing but very short and concise, maybe 'Halftype saved you <21 minutes> (of typing? dunno if we should add that) this week' with the time colored in, and other stats below. And i'm wondering if G's bar chart looks better than the simple one we have now."

- `round4/index.html`: A round 3's B for reference; B "saved you 21 minutes this week"; C the same with "of typing"; D time first in ink; E C with G's glass-track pills; F C with pills and no tracks, today in ink. Same real week as round 3.
- `round4/options.png`: frozen screenshot.

Recommendation: C with flat bars ("of typing" keeps the claim to what we measure; G's empty tracks read as missed goals on real data, and its gradient repeats the headline's colour). Pick: pending.

## Round 5: C with fewer lines

John: "C looks good but there's so many horizontal lines everywhere? Show me some improved designs of C (inc different designs for the other stats)"

- `round5/index.html`: A round 4's C; B the same figures with no dividers; C the stats as one quiet grey line under the sentence; D labels above numbers; E soft chips; F the stats under the chart; G chart and stats in one white panel. Every option but A keeps only the chart's baseline (G: none).
- `round5/options.png`: frozen screenshot.

Recommendation: C (the quiet line). Pick: E (John: "E visually does differentiate everything, which i appreciate"), with two fixes: the chips are faint white glass with a hairline so they don't read as the Week / Month / All control, and each explains itself on hover. Time saved uses a fixed 40 wpm (200 keys a minute) and words are letters ÷ 5 for now: measuring each user's speed and counting Korean words are open. The chart and the All dots now show time saved, not Tabs. `built/round5-stats-week.png`, `-month`, `-all`: the shipped page, from `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots/stats` on 2026-11-10 (sample data).

Then the personal model comparison got a heading ("Your personal model", John: "what is this?") and one bar per row from zero, glass for with it and grey without: `built/round5-personal-model.png`.
