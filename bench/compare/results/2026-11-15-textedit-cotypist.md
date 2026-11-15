Run 2026-11-15T054750Z on Apple M5, 16 GB, macOS Version 27.0.1 (Build 26A434). Typed into a TextEdit document (plain text, Helvetica 17). Apps: cotypist 2026.5.2. 64 English (Taskmaster-1) and 0 Korean (SmileStyle) sentences from bench/compare/ids.tsv, typed at log-normal delays around 264 ms with a 1.5 s probe after every third word.

| App | Text | Sentences, keys | Keys saved (95% CI) | Keys with a ghost | First word right | Right / wrong ghosts per 100 keys | Ghost after a key, fresh p50 / p90 (n) | 1.5 s probe: none, p50 (n) | Mid-syllable ghost (n) | Tabs, wrong, as OCR read | Footprint median / max | Model resident | CPU |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| cotypist | en | 64, 2554 | 9.9% (6.5-13.8) | 21.4% | 24.5% | 5 / 16 | 141 ms / 164 ms (43) | 96.1%, 147 ms (103) | - | 112, 0, 110 | 305 MB / 474 MB | - | 2% |

**Cotypist hit its free plan's daily cap part-way.** It suggested on 25 scored sentences, faded in the 26th (9 keys with a ghost of 68) and showed nothing in the 38 after (the harness: "no suggestion in three sentences running"), so the row above, over all 64, is not its number.

**What to quote: the 25 sentences before the cap, against Halftype on the same 25 in TextEdit** (2026-11-14-textedit.md, 0.1.19 at its defaults, Gemma 4 E2B; the same sentences, keys and typist): keys saved, Cotypist 26.7% (95% CI 21.9-31.7), Halftype 25.1% (19.7-30.6), paired -1.6 points (-6.6 to +3.8), **a tie**; Halftype ahead in 7, level in 5. Bootstrap over sentences, 10,000 resamples. Both in TextEdit (plain text, Helvetica 17, the Mac switched to light), Cotypist 2026.5.2 at its defaults with its personal prompt cleared, launched without `-j` (README). On 25 sentences the interval is wide: a difference under about 6 points can't be told.

How the 25 were scored: the first 25 records of each run's `sentences.jsonl` (Cotypist's in run order; Halftype's matched by `sentence` id), keys saved = 1 − Σ`pressed` / Σ`total` (1,055 keys each); the CI resamples sentences with replacement, seed 1.

Memory on the same 25: footprint median 390 MB (max 474) for Cotypist, 216 MB (max 242) for Halftype: the first 25 entries of each run's `footprintMB` in `resources.jsonl` (sampled after each sentence). Model pages on top: Halftype 1,434 MB resident in its run; Cotypist's weren't read here, 1.5 GB at rest (docs/measuring.md). CPU and power are not quoted: CPU is one figure over all 64 sentences, 38 of them silent, and power wasn't recorded.
