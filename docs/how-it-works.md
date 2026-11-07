# How Itda works

Every key becomes one question: does the current suggestion still fit? If not, ask the model and show the answer only if it's sure. Everything else is there to keep that fast and to make it work under a Korean input method.

```
Accessibility notification from the focused field
  |
  v
Read once: { text before, marked text, text after, caret rect, font, secure? }      no polling
  |
  +-- secure, or text after the caret ---------------------------------> no suggestion
  |
  +-- the suggestion still fits what's typed --------------------------> show the rest, no model call
  |
  v
Prompt: frozen context + window up to the last whole word
        held out: the half-typed word, and a composing syllable
  |
  v
llama.cpp, in process: greedy; output must fit what was held out, by bytes or 2-set keys
        stop at newline, punctuation, 8 tokens, or the word that takes it below e^-1; the latest request wins
  |
  v
Gate: P(first word | it fits what was typed) >= e^-0.7 ------- no ----> no suggestion
  |
  v
Grey text at the caret, in a panel that takes no focus
  |
  +-- Tab: next word       2-set: real key presses, so the input method finishes the syllable
  +-- Shift-Tab: all       otherwise: inserted as text, in short chunks, with no clipboard
  +-- Esc or any other input: passes through to the app
```

The pure logic is in `Sources/ItdaCore` and has no model or GUI, so `swift test` can check it. `ItdaEngine` holds llama.cpp, and `ItdaApp` holds Accessibility, the key tap and the panel.

## Decisions, by effect

Every number is from a replay of real typing, scored by exact match, on an M5. How to read them: [measuring.md](measuring.md).

| # | Decision | Evidence | Rejected |
|---|---|---|---|
| 1 | Hold out the half-typed word and force it back | Useful mid-word in English 7.7% to 50.8% (paired, n=130, Gemma; 95% CI of the gain +34 to +52 points). Requiring at least two characters saved: 7.7% to 37.7% | Trimming the output afterwards; matching strings token by token |
| 2 | Gate on the first word's probability among tokens that fit, with one threshold, -0.7 | English 82-85% right at 45-49% coverage on three models. A plain first-token gate at the same precision covers only 11-13%. No gate: 50-53% right | Mean or minimum logprob, length rules, a cumulative floor |
| 3 | Withhold a composing syllable, force the output to fit its 2-set keys | Keys saved per request mid-syllable, public Korean: 0 sending it, 0.34 withholding, 0.69 forced (n=1,099). More wrong ghosts: 18.2% against 8.4% | Sending it, which can never match; going silent under an input method |
| 4 | Tab takes one word | Characters saved per request: 0.92 next word, 1.69 Tab repeated, 0.26 accepting everything at once | Tab accepts all |
| 5 | A frozen head and a window start that moves in steps | 8.4 prompt tokens per key across all requests, English. The next key after a 226-token prompt: 1 token, 13 ms, against 450 ms from nothing | `--cache-reuse`, a window that slides per key |
| 6 | Reuse the suggestion while it fits | No model call on 48% of English keys and 27% of Korean, timed | Speculative prefetch: more moving parts, unmeasured |
| 7 | The prompt never ends in a space | English word starts, useful 0-5% to 13-18% (paired, n=39, an earlier bench) | |
| 2b | Stop before the first unsure word, and don't show a first word of under three keystrokes | English test threads, Kanana: grey characters that were right went from 19% to 75%, and ghosts on 45% of requests to 18%, for 18% less saved per request. See measuring.md | Filling all 8 tokens: only 23% of ghosts were right to the end |
| 8 | llama.cpp in process, reading the logits | The gate needs true probability over every allowed token, which `n_probs` can't give. Cancelling during prefill takes 24 ms (p50), which a server disconnect doesn't offer | `llama-server` |
| 9 | One raw path, no chat template or fill-in-the-middle | Fill-in-the-middle lost and document framing added nothing. All three models tested run on one path with no per-model code | Per-model tables |
| 10 | Default model Qwen 3.5 0.8B, 0.5 GB, Apache-2.0. English comes first; Korean has to work, not lead | Nine small models replayed on English, November 2026. Keys saved by Tab per request, English test set, against Qwen 3.5 2B: -0.09 to +0.01 (paired, by thread), at 41% of its size, first word 53 ms against 74. Whole messages 21.6% against 23.1%. Newer models (LFM3 1.7B, Kanana 2 3B, Ternary Bonsai 2, a 2-bit Gemma) lost; Granite 4.2 3B and Gemma 4 E2B only tie Qwen 2B at its precision. See measuring.md | Kanana 1.5, the default until 0.1.0: Korean clearly better (own messages 1.03 against 0.60 keys per request), English a little behind. Stays in the window with Qwen 3.5 2B and Gemma |
| 11 | Accessibility only | OCR-like context wasn't significantly better than Accessibility's, and it needs Screen Recording | OCR, clipboard, history, personal n-grams |
| 12 | Wired memory held for 15 s, not 3 minutes | ggml's default keeps 1.5 GB pinned for 3 minutes after the last request. 15 s leaves requests while typing unchanged within noise. Turning residency off adds 25-45 ms per request | Residency off |
| 13 | A key's hide waits one frame | Hiding at once blanked the ghost on 46 of 48 keys, about 4 flashes a second at 60 Hz. One frame later: none, in a native host | Hiding at once |

## Things that didn't earn their place

- **Warm-up at load:** no benefit, 42 ms with and 30 ms without (first short request, five runs each).
- **Prefill batches of 128:** cancel went to 227 ms. 8 and 16 were noisy and no better than 32.
- **Keeping 1400 tokens of context:** 900 saves about 50 MB, and the longest prompt seen was 614.

**Not built, and not compared:** beam search and reranking. Greedy with the gate was the simplest thing that met the bar, and no test here says a beam wouldn't beat it.

## How to get these numbers yourself

[measuring.md](measuring.md) has the commands. The memory and frame numbers come from `scripts/e2e.sh`, on your Mac, with no private data. The prediction numbers come from `itda-replay` at the tag `bench-1`, on text you supply: bring your own, or use the public Korean dataset named in [CREDITS.md](../CREDITS.md).

## Not verified

- **Korean in Chromium-based apps:** the plan rests on the same input method, but it has only run in a native field. [live-test.md](live-test.md) is the check.
- **The Tab user in replay** walks a recorded trace, so later requests don't react to what an accept changed.
- **Power** isn't measured, because `powermetrics` needs sudo. True cold start wasn't forced either: the slowest first load seen was 5.8 s, after other models had evicted its pages.
