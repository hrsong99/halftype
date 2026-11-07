# How Itda works

Every key becomes one question: does the current suggestion still fit? If not, ask the model and show the answer only if it's sure. Everything else is there to keep that fast and to make it work under a Korean input method.

```
Accessibility notification from the focused field
  |
  +-- Tab couldn't reach us: Secure Input, or the tap is off -----------> no read, no model, no suggestion
  |
  v
Eligible, asked on every read: text role, not secure, value settable -- no -> no suggestion
  |
  v
Read once: { text before, marked text, text after, caret rect, font }      no polling
  |
  +-- text after the caret ---------------------------------------------> no suggestion
  |
  +-- the suggestion still fits what's typed --------------------------> show the rest, no model call
  |
  +-- no caret rect, so nowhere to draw --------------------------------> no model call
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
Grey text at the caret, in a panel that takes no focus; Tab can take only what was drawn
  |
  +-- Tab: next word       2-set: real key presses, so the input method finishes the syllable
  +-- Shift-Tab: all       otherwise: inserted as text, in short chunks, with no clipboard
  +-- Esc: hides it and goes no further; with no ghost it's the app's
  +-- any other input: passes through to the app
```

Each place this path stops records why, with no text in it: no field, text after the caret, not sure, no caret, no font, and so on. The menu and the window show it as one line, the window only once it has held for 0.4 s, so typing doesn't flicker it. The same record tells the menu-bar icon that Secure Input came or went, which nothing else announces.

**The tap.** It sits in line with every key and click on the Mac, so it holds to the permission. Any permission change takes it down at once (`com.apple.tcc.access.changed`, undocumented), and one loop in `KeyTap` then retries each second until `tapCreate` works, and stops. Each try asks `AXIsProcessTrusted` first, so the loop doesn't raise the system's dialog before the user has asked for it: a no there skips `tapCreate`, so a stale no would keep the tap away until relaunch (not seen). A yes is only let through, as it can stay true after a revoke, and `tapCreate` then refuses. A tap the system disabled is re-enabled on activation and on wake, with no timer.

**Chromium and Electron** build their accessibility tree only when a client asks. Itda asks once per process, when it first watches the app. An app that answers Electron's documented `AXManualAccessibility` as settable gets that. An app whose bundle has Chromium's renderer helper, `<Name> Helper (Renderer).app`, gets `AXEnhancedUserInterface`, unless the flag is already on or VoiceOver is on, asked at each set as VoiceOver comes and goes. Native apps get nothing, as the flag slows window managers. Chromium waits 2 s after the flag and starts over on every set, so it is set again only if it reads off 3 s or more after the last look. A fresh Chromium may say nothing once its tree is ready, so while no field can be read, a key looks again, on the watcher queue, with at most one look queued or running. A process is known by its pid and launch time, so a reused pid is a new process; one with no launch time is primed again at each bind and never restored, as its pid may be another app's by then. On quit, every model closes first, without waiting on the watcher, and no request can load one again. Then `AXEnhancedUserInterface` goes back off where Itda turned it on and that process still runs, as best it can in 0.5 s (two AX timeouts) including the wait for the watcher; Electron's switch stays, as reading it back can't tell it was ours.

**Web editors.** Between paragraphs, Chromium's `AXValue` has a newline that its selection leaves out, so the caret's index runs one short per paragraph. When the value has a newline, `AXStringForRange` up to the caret is read: if it isn't the value's start, the index is walked through the value, and later range reads are asked in the host's own offsets. A field whose text doesn't line up, or whose range read fails or comes back short, isn't read, in any host: a failed read proves nothing about which offsets the host uses. Native views answer the range read with the same text. A caret at a paragraph's start counts as the end of the one above. **Page zoom** isn't in the font size Chromium reports, while the caret is on screen, so from a web caret the ghost's size follows the caret's height once that is over 1.15 times the font's line, or under 1/1.15 (about 0.87). The band is an estimate, not measured in a host: the page's font isn't named, and from common fonts' published metrics their line can differ from the system font's by about a tenth. A font whose line is 0.9 of ours at 125% stays unscaled. Live-test step 20 is the check.

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
| 10 | Default model Kanana 1.5 2.1B base, 1.4 GB, Apache-2.0 | Korean ahead of Gemma on the author's messages (1.03 against 0.54 keys per request, CI +0.17 to +0.80), level with Qwen. English a little behind (22.1% against 23.2%, same 40 messages), at 40% of Gemma's size | Gemma as default: stays one menu item away, with any GGUF |
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
