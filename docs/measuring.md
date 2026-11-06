# What the numbers mean, and how to get them yourself

All of it on an M5 with 16 GB, llama.cpp b12167, Kanana 1.5 2.1B base (1.4 GB).

## Memory: what a user actually pays

`scripts/e2e.sh --measure <gguf>` runs the real path with the real model on a private window: 280 keys of typing, idle, unload, 20 reloads.

| State | Activity Monitor's Memory (footprint) | Wired, system-wide | RSS |
|---|---|---|---|
| Typing, and for 15 s after | 250-310 MB | **+1.5 GB** | 1.5-1.6 GB |
| Stopped, model loaded, up to 5 minutes | 250 MB | +0 | 1.5 GB, evictable |
| Unloaded, after 5 idle minutes | 79 MB, the shipped app | +0 | 72 MB |

- **While you type, the true cost is 1.5 GB of RAM nothing else can use, plus the footprint.** Metal wires the model's pages through a residency
  set. Activity Monitor's per-process Memory doesn't show it; the Wired figure at the bottom of its window does. `MTLDevice.currentAllocatedSize` says 1,472 MB.
- RSS is the wrong number in both directions: it counts the weights the same whether wired or evictable. Footprint alone is too kind while typing.
- By default ggml keeps this up for 3 minutes after the last request. Itda sets 15 s (`GGML_METAL_RESIDENCY_KEEP_ALIVE_S`). Requests while typing are unchanged within noise, 98-123 ms across runs.
  The first after a pause takes about 100 ms rather than 70. Turning residency off altogether adds 25-45 ms to every request, so it's not used.
- `use_mmap` doesn't save you while typing: with it on, the default, the mapped pages are the ones wired. Off wasn't tested.
- Unload and reload doesn't leak: footprint goes 158 MB to 160 MB over 55 cycles, after a first step up. Metal's own caches take that step.

CPU: the shipped app, idle, 0.13% to 0.27% of a core over 60 s, loaded or unloaded, measured from outside. Typing at about 5 keys a second, 7-8%. Power isn't measured: `powermetrics` needs sudo.

## The frame a key's ghost stays

After a key the tap disarms at once, and the panel hides one frame later unless the field's update has drawn it again. Whether a host will answer a key at all can only be told by waiting.
Typing 48 letters through a ghost in the private window of `scripts/e2e.sh --flicker`, with `screencapture -v -R<window>` running and each recorded frame checked for ink on the ghost's line:

| Hide after a key | Keys that blanked the ghost | What reached the screen |
|---|---|---|
| At once, on the next main-thread turn | 46 of 48, hidden 6-8 ms (p50, p90) | 22 single blank frames at 60 Hz, about 4 flashes a second |
| One frame later (shipped) | 0 from typing | 0 blank frames (only the no-ghost a mid-word line end asks for) |

A native host answers in under 8 ms. **Chromium's time isn't measured**: if it is over a frame the ghost still blanks there. `docs/live-test.md` step 12 is that check.

## How well it predicts

The numbers behind the design (keystrokes saved, the gate threshold, composition states) came from a replay harness: real typing delays, the real engine, the real policy.
It isn't in this tree, as it would add 400 lines and hold the engine's API open for one tool. It's at the tag `bench-1`:

```sh
git checkout bench-1
swift run --disable-keychain itda-replay --model model.gguf --in yours.jsonl --out trace.jsonl
```

`yours.jsonl` has one `{"context": "...", "text": "..."}` per message: `text` is what was typed, `context` what was on screen. Any text of your own will do. The trace holds that text, so keep
it private. Scoring is exact match, so a good paraphrase scores zero. No results quoting anyone's text are published here.

Each suggestion is also unit tested without a model or GUI (`swift test`), and against a real model with `ITDA_MODEL=<gguf> swift test`.
