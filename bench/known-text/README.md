# Known text

How well each model finishes text everyone knows, as Halftype would show it. 200 English lines, 50 per group, one per line:

| File | What | Source |
|---|---|---|
| `quotes.txt` | Famous quotes, speech and book openings | Public domain: US government speeches, the King James Bible, Shakespeare, 19th-century novels and poems; a few very short attributed lines (Churchill, Armstrong, Edison) |
| `idioms.txt` | English idioms and proverbs | Traditional, no author |
| `stock.txt` | Stock phrases of everyday email, chat and web forms | Written for this benchmark |
| `articles.txt` | Encyclopedia-style lead sentences on well-known subjects | Written for this benchmark in the style of Wikipedia lead sentences, paraphrased; no text copied |

Lines were picked by hand as the best-known examples of each kind, before any model was run. No one's messages are in here.

## Run

```sh
bench/known-text/run.sh                 # the four models in ~/Library/Application Support/Halftype, one after another
bench/known-text/run.sh model.gguf ...  # others
```

It builds `KnownText.swift` as an extra target in a throwaway worktree (`../halftype-known-text`, the app's `Package.swift` is untouched), so it runs the app's own `Engine`, `Prompt`, `Stop`, `Gate` and `Follow` at this commit. Set `RUN_PREFIX` to a lock wrapper to run behind other model jobs. Writes `results/<model>.jsonl.gz` and `results/summary.md`. About 5 minutes per small model alone on an M-series Mac.

Each line is typed with no screen context, synchronously: every position waits for its answer, so speed doesn't count.

- **Positions**: the caret just after a space, and two letters into a word that goes on.
- **Shown**: the gate (-0.7) passed and the first word is at least 3 keys, as the app decides.
- **Right**: the first word shown is exactly the next word (`Score.swift` at `bench-1`, exact match).
- **Saved**: a Tab user types each even line letter by letter, pressing Tab (one key, one word) whenever a right word shows. Keys not pressed, of the line's characters.

## Results, 8 November 2026

`results/summary.md`, at Short and Normal, the defaults then (Normal is now When Sure). Saved, whole lines (100 lines, 25 per group), against Qwen 3.5 0.8B with a 95% bootstrap CI over lines: Qwen 3.5 2B +9.6 points (+7.7 to +11.6), Kanana 1.5 +13.4 (+10.7 to +16.1), Gemma 4 E2B +15.7 (+12.8 to +18.7). The gap is widest on quotes (+17 to +29) and idioms (+10 to +21), and 4 to 9 points on stock phrases and article prose. Run times alone, M-series, sharing the Mac: 3.2, 6.3, 4.9 and 6.1 minutes for Qwen 0.8B, Qwen 2B, Kanana and Gemma.
