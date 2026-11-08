# What the numbers mean, and how to get them yourself

All of it on an M5 with 16 GB, llama.cpp b12167. Unless it says otherwise, on Kanana 1.5 2.1B base (1.4 GB), the default until 0.1.0. The default is now Qwen 3.5 0.8B (0.5 GB): see [Choosing the default model](#choosing-the-default-model). Its memory is in the next section; the rest of that section is Kanana's.

## Memory: what a user actually pays

**Qwen 3.5 0.8B, the default**, the same run on 2026-11-07: while typing (282 keys in 52 s), `MTLDevice.currentAllocatedSize` 562 MB, system wired +542 MB over before loading, footprint 267 MB, CPU 7% of a core. Idle with the model loaded, wired back to where it started; unloaded, Metal 2 MB. 20 reloads: footprint 171-214 MB, no growth. The first run of the harness crashed in its own window's Accessibility read, off the main thread; the second passed.

Kanana 1.5 2.1B, the default until 0.1.0:

`scripts/e2e.sh --measure <gguf>` runs the real path with the real model on a private window: 280 keys of typing, idle, unload, 20 reloads.

| State | Activity Monitor's Memory (footprint) | Wired, system-wide | RSS |
|---|---|---|---|
| Typing, and for 15 s after | 250-310 MB | **+1.5 GB** | 1.5-1.6 GB |
| Stopped, model loaded, up to 5 minutes | 250 MB | +0 | 1.5 GB, evictable |
| Unloaded, after 5 idle minutes | 79 MB, the shipped app | +0 | 72 MB |

- **While you type, the true cost is 1.5 GB of RAM nothing else can use, plus the footprint.** Metal wires the model's pages through a residency
  set. Activity Monitor's per-process Memory doesn't show it; the Wired figure at the bottom of its window does. `MTLDevice.currentAllocatedSize` says 1,472 MB.
- RSS is the wrong number in both directions: it counts the weights the same whether wired or evictable. Footprint alone is too kind while typing.
- By default ggml keeps this up for 3 minutes after the last request. Halftype sets 15 s (`GGML_METAL_RESIDENCY_KEEP_ALIVE_S`). Requests while typing are unchanged within noise, 98-123 ms across runs.
  The first after a pause takes about 100 ms rather than 70. Turning residency off altogether adds 25-45 ms to every request, so it's not used.
- `use_mmap` doesn't save you while typing: with it on, the default, the mapped pages are the ones wired. Off wasn't tested.
- Unload and reload doesn't leak: footprint goes 158 MB to 160 MB over 55 cycles, after a first step up. Metal's own caches take that step.

CPU: the shipped app, idle, 0.13% to 0.27% of a core over 60 s, loaded or unloaded, measured from outside. Typing at about 5 keys a second, 7-8%. Power isn't measured: `powermetrics` needs sudo.

## Against other apps (landing page, 2026-11-09)

Cotypist, Cotabby and KeyType at rest, each with its default model: the method, the numbers and the traps are in [site/compare/README.md](site/compare/README.md), with the script that measured them. While typing (speed from the screen, keys saved, first word right, memory, CPU, Korean mid-syllable), with macOS's predictions too: [bench/compare/README.md](../bench/compare/README.md), not run yet.
- System-wide wired memory is useless while other agents run: it swung 4.9-7.1 GB with one app idle. Use `footprint -p`.
- Before measuring Halftype the same way, check `pgrep -lf Halftype.app`: another session's dev build may already be running. Check `defaults read app.halftype.Halftype modelPath` too, as it may not be the default.

## The frame a key's ghost stays

After a key the tap disarms at once, and the panel hides one frame later unless the field's update has drawn it again. Whether a host will answer a key at all can only be told by waiting.
Typing 48 letters through a ghost in the private window of `scripts/e2e.sh --flicker`, with `screencapture -v -R<window>` running and each recorded frame checked for ink on the ghost's line:

| Hide after a key | Keys that blanked the ghost | What reached the screen |
|---|---|---|
| At once, on the next main-thread turn | 46 of 48, hidden 6-8 ms (p50, p90) | 22 single blank frames at 60 Hz, about 4 flashes a second |
| One frame later (shipped) | 0 from typing | 0 blank frames (only the no-ghost a mid-word line end asks for) |

A native host answers in under 8 ms. **Chromium's time isn't measured**, and John saw the ghost flash on each key in T3 Code (Electron), so it is over a frame there.

Since 2026-11-09 a key that types the ghost's next letter doesn't blank it: the panel stops drawing that letter in place and skips the frame's hide (`KeyTap.typesNext`, `GhostPanel.trim`) until the host's update draws and arms it again. Tab stays disarmed in between, as after any key, so it can only take what the host has confirmed (Codex: an armed guess let Tab insert `here` after a `t` a web editor ate). Only another key hides after the frame. A host that never shows the letter loses the ghost after `Watcher.unanswered`, 0.5 s.

Measured live on 2026-11-09 (the app run from the shell with a temporary timestamp trace, keys from `scripts/live-keys.swift` at 98 ms apart, typing ` the lates` through a ` the latest` ghost in a plain textarea in ego lite, Chromium): every key trimmed the drawing at once and none hid it; Chromium's update redrew it 12-29 ms after the key (p50 about 20 ms, 10 keys). One frame is 16.7 ms, so the old frame-then-hide blanked most keys there. The table above is from before this, in the private window.

## How well it predicts

"Useful" below means the first word is right, which hid a bad experience: a ghost averaged 19 characters and four words, and only 19% of those grey characters were right. Offline replay of the English test threads (2,400 requests, 120 messages, Kanana 1.5; Qwen 3.5 2B within a few points), with the floor and minimum picked on dev threads:

| Policy | Ghost on | First word right | All of the grey right | Grey chars right | Grey chars per ghost | Chars saved per request |
|---|---|---|---|---|---|---|
| All 8 tokens | 45% | 85% | 23% | 19% | 19.4 | 0.56 |
| Stop before a word below e^-1 | 45% | 85% | 79% | 76% | 3.5 | 0.56 |
| And a first word of at least 3 keys | 18% | 80% | 74% | 75% | 5.1 | 0.46 |

The replay counts characters including the leading space, while the app counts keystrokes, so in Korean the two minimums differ. It doesn't cover Korean accurately, because it can't score a syllable still being composed. The keystroke figures elsewhere on this page were measured before this change.

**Judging the three-key minimum on the whole ghost (2026-11), on the branch `bench-2` (local, not yet tagged),** which replays the shipped policy (stop floor, gate, minimum). Tab repeated or Shift-Tab takes the lot, so `to the` is worth showing although `to` is short. Picked on the English dev threads, confirmed on test (2,400 requests each): keys saved per request with one Tab +0.111 on dev (CI +0.090 to +0.133) and +0.110 on test (CI +0.089 to +0.132), for wrong and shown per request +0.9% and +0.6%. A minimum of four saved nothing with one Tab. Timed English, 1,200 keys at load under 2: keystrokes saved 17.1% to **18.2%** (paired CI +0.6 to +1.9 points). CIs are paired bootstraps over messages.

**Forcing a typed space back in English too,** as the composing case always did: when the field ends in a space, the ghost must start with one. Dev +0.008 keys per request (CI +0.002 to +0.016), test +0.006 (CI +0.001 to +0.013), wrong and shown +0.0-0.1%. Timed English, 1,200 keys: 17.1% to **17.8%** saved (paired CI +0.1 to +1.4 points); its timing was taken while other jobs loaded the Mac, so its 61 ms first displayable word against 58 ms is approximate. Measured separately from the minimum above, not combined.

Your own phrases didn't help. A next-word lookup from strictly older messages, tried ahead of the model, was right about as often (78%) but saved less: 0.10 alone and 0.50 merged, against 0.56.

The replay harness runs the real engine and policy with real typing delays. It isn't in this tree, as it would add 400 lines and hold the engine's API open for one tool. It's at the tag `bench-1`:

```sh
git checkout bench-1
swift run --disable-keychain itda-replay --model model.gguf --in yours.jsonl --out trace.jsonl
```

`yours.jsonl` has one `{"context": "...", "text": "..."}` per message: `text` is what was typed, `context` what was on screen. Any text of your own will do. The trace holds that text, so keep
it private. Scoring is exact match, so a good paraphrase scores zero, and it's in `Sources/itda-replay/Score.swift` at that tag.

Results below are for Kanana 1.5 at the shipped threshold, -0.7, unless a cell says otherwise. Typing delays come from a 107-key histogram, p50 264 ms. Later commits only removed unused code from the engine and policy; the app's accepting and display have changed since, and replay doesn't cover those.

**The text.** English: the author's own messages, each with the message before it as context. They aren't published, and neither is anything quoting them. Korean, public: dialogue from [SmileStyle](https://github.com/smilegate-ai/korean_smile_style_dataset), which is other people's style-transfer text, so it isn't how anyone writes messages. Korean, own: 70 of the author's messages, with Hangul inside mostly English text. That's a small sample, and half of them come from threads also used to fit the threshold on English. Threads are split, so none is in both the fitting and test sets. A real input method wasn't used in replay: composing states come from a model of 2-set.

**The shipped policy (2026-11-08, branch `bench-2`):** the floor, gate and whole-ghost minimum, with typed spaces forced back. Timed replay, 1,200 keys per language, load under 5 for English and under 3 for Korean; the English timing is approximate.

| What | English | Korean, public |
|---|---|---|
| Keystrokes saved, whole messages, Tab costs one key | **18.2%** (17.1% before the two changes above, paired CI +0.6 to +1.9 points) | **8.1%** (8.2% before, CI -0.5 to 0.0) |
| Tab repeated | 21.5% | 8.2% |
| Shown ghosts with the first word right | 82.6% | 54.9% |
| Keys with a wrong ghost visible | 6.8% | 7.7% |
| Keys with no model call | 29.7% | 12.8% |
| First displayable word, p50 of requests that got that far | 60 ms, 92% got there | 98 ms, 67% |

Combined, the two changes saved what the minimum alone did in English. Korean, own text wasn't replayed again.

**Before ghosts were cut short (bench-1),** for comparison: ghosts ran to 8 tokens, so more keys were saved and far more grey text was wrong.

| What | English | Korean, public | Korean, own |
|---|---|---|---|
| Keystrokes saved, whole messages, Tab costs one key | **22.8%** (1,200 keys) | **8.8%** (1,200 keys) | **13.4%** (1,800 keys) |
| Without the syllable replacement | | 7.1% | 11.9% |
| Same, typing at twice the speed | 20.0% (800 keys) | 7.1% (800 keys) | |
| Suggestions shown that were right | 84.9%, 919 of 1,082 (thread CI 82-88) | 31-34%, across three models | 55-61% on Hangul requests, across three models |
| Coverage | 45.1% | | |
| Wrong and shown, per request | 6.8% | | |
| Keys with no model call | 48.2% | 26.9% | 28.1% |
| First displayable word, p50 of requests that got that far | 60 ms, 86% got there | 102 ms, 62% | 114 ms, 58% |
| Visible before the next key | 62.8% | 37.2% | 39.1% |

- **The gate doesn't work for public Korean.** Precision stays at 31-35% at every threshold from -1.2 up, and half of the wrong ghosts have at least two characters right. It's the reason for the first limit in the README.
- **Gate, English test set, all three models tried:** 82-85% right at 45-49% coverage, wrong and shown 7-9%, against 50-53% right and 44-46% wrong with no gate. 2,400 requests per model. Without conditioning on the fragment: 84-89% right, at 11-13% coverage.
- **Korean, by composition state, keys saved per request:**

| Set | State, n | Withhold | Send as text | Forced by 2-set keys (shipped) |
|---|---|---|---|---|
| Public | Mid-syllable, 1,099 | 0.34, wrong 8.8% | 0, wrong 8.4% | **0.69**, wrong 18.2% |
| Public | Syllable final, 724 | 0.34, wrong 11.6% | 0.59, wrong 9.9% | **0.68**, wrong 22.1% |
| Own | Mid-syllable, 455 | 0.75, wrong 8.1% | 0, wrong 4.8% | **1.11**, wrong 12.3% |
| Own | Syllable final, 287 | 0.66, wrong 7.7% | **1.13**, wrong 3.8% | 0.91, wrong 12.5% |

Where the syllable is already final, sending it is better on the author's own text. Forced wins overall, on 742 requests (1.03 against 0.44, CI +0.26 to +0.90), and needs no pause heuristic. So it stays.

The live input method is a separate check, `scripts/e2e.sh --ime`: every composing state of 17 hard words, Tab finishing each in a native field. It needs you idle for 15 s, as it switches the system's input source.

Each suggestion is also unit tested without a model or GUI (`swift test`), and against a real model with `HALFTYPE_MODEL=<gguf> swift test`.

## Choosing the default model

November 2026, the same replay (`itda-replay` at tag `bench-1`, threshold -0.7) on the newest small base models that fit in memory. English decides; Korean has to work. Tab keys per request, English test threads (2,400 requests per model), with a 95% CI paired by thread against Qwen 3.5 2B. Saved: whole messages with typing delays, the same 40 English messages (800 keys). Korean, own: keys per request on Hangul, 70 of the author's messages. Timed runs shared the Mac with other work.

| Model | File | Right when shown | Wrong and shown, per request | Tab keys per request | Saved, whole messages | First word, p50 | Korean, own |
|---|---|---|---|---|---|---|---|
| Granite 4.2 3B | 2.24 GB | 77.6% | 12.2% | 1.06, +0.01 to +0.14 | 23.8% | 79 ms | 0.49 |
| Gemma 4 E2B | 3.43 GB | 82.3% | 8.7% | 1.00, -0.04 to +0.08 | 23.2% | 71 ms | 0.54 |
| Qwen 3.5 2B | 1.28 GB | 81.6% | 9.0% | 0.98 | 23.1% | 74 ms | 0.88 |
| Kanana 1.5 2.1B | 1.39 GB | 84.9% | 6.8% | 0.92, -0.12 to +0.01 | 22.1% | 60 ms | 1.03 |
| **Qwen 3.5 0.8B** | **0.53 GB** | 81.5% | 8.7% | 0.94, -0.09 to +0.01 | 21.6% | 53 ms | 0.60 |
| Ternary Bonsai 2 2B, Q2_0 | 0.55 GB | 78.8% | 10.0% | 0.91, -0.13 to -0.02 | 19.8% | 73 ms | 0.68 |
| Kanana 2 3B | 1.98 GB | 82.7% | 7.9% | 0.90, -0.15 to -0.02 | 19.2% | 74 ms | 0.81 |
| Gemma 4 E2B QAT, 2-bit | 2.19 GB | 70.0% | 14.2% | 0.78, -0.27 to -0.12 | 19.1% | 61 ms | 0.29 |
| LFM3 1.7B | 1.10 GB | 78.7% | 8.6% | 0.73, -0.32 to -0.18 | 17.0% | 63 ms | 0.41 |

- Granite leads by showing more wrong suggestions. At its own threshold for 80% precision on dev threads (-0.5) it gives 0.96 keys at 83.0%, level with Qwen 3.5 2B at 1.75 times the size.
- Qwen 3.5 0.8B ties Qwen 3.5 2B on English within the CI, at 41% of the size and with the quickest first word, so it's the default. What it gives up is Korean: own messages 0.60 against 0.88 keys per request (CI -0.52 to -0.10).
- Qwen 3.5 0.8B against Kanana 1.5, the old default, in full: English test 922 of 1,131 shown right (81.5%), coverage 47.1%. Whole messages: English 21.6% against 22.1% (800 keys), Korean public 4.8% against 8.8% (1,200 keys), Korean own 10.8% against 13.4% (1,800 keys). Korean public suggestions on Hangul right when shown: 20.9% against 33.7%. First displayable word p50: 53, 97 and 102 ms against 60, 102 and 114 ms. No model call on 47%, 20% and 26% of keys against 48%, 27% and 28%.
- Not tried: models of 3.5 GB or more, community fine-tunes, and Ternary Bonsai's smaller packings, which need a fork of llama.cpp. Gemma 4's tokenizer fix of 3 November 2026 changed no weights and came after these files.

## Length and How Often

The window's two settings move the two numbers above: Length the floor that ends a suggestion (-1, -2, -3), How Often the gate's threshold (-0.3, -0.7, -1.2, and Always with no gate, not replayed here; the no-gate figure in the README is the nearest). Defaults are Short and Normal, the fitted values. The Try It window ignores both and always runs with no floor and no gate, so a first try shows a suggestion at every pause. Offline replay, Qwen 3.5 0.8B, English test threads, 2,400 requests, Tab one word, the first word at least 3 keys (`reviews/audit-2026-11/quality-aggregates/length_freq.py` in the bench repo):

| Setting | Shown, of requests | First word right | Wrong and shown, per request | Grey characters per ghost | Grey characters right | Characters saved per request |
|---|---|---|---|---|---|---|
| Short, Normal | 20.0% | 75.2% | 5.0% | 5.2 | 76.7% | 0.552 |
| Medium, Normal | 20.0% | 75.2% | 5.0% | 7.1 | 61.4% | 0.580 |
| Long, Normal | 20.0% | 75.2% | 5.0% | 9.2 | 49.8% | 0.585 |
| Short, Less | 12.0% | 89.2% | 1.3% | 5.3 | 85.2% | 0.395 |
| Short, More | 30.6% | 58.2% | 12.8% | 4.9 | 63.7% | 0.642 |

Longer adds little, as Tab takes one word and more of the extra words are wrong. No floor at all gives 17 characters, 27% right, for the same savings as Long. Suggestions stop at 8 tokens whatever the setting. Not measured in timed replay or on Korean.

