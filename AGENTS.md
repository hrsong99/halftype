# Itda: what a future agent must know

A menu-bar Mac app: inline Korean and English suggestions from a local model. Read `docs/how-it-works.md` first.

## Must not break
- **No private text, ever.** Nothing from anyone's messages goes in this repo: not tests, docs, commit messages or screenshots. Test strings are invented, and benchmark results are aggregates only. Replay traces hold typed text and stay out.
- **Privacy claims in the README are promises.** No network except `ModelStore`'s model URLs and Sparkle's update feed, no typed text written to disk or logs, no Screen Recording, secure fields skipped. A change that touches one changes the README in the same commit.
- **Licences.** AGPL, GPL and unlicensed projects in `CREDITS.md` gave ideas only. No code from them. A new borrowed idea gets a row there, with its licence checked.
- **Every number carries how it was measured**, here or in `docs/measuring.md`. Remeasure rather than edit one by hand.

## Commands
- Tests: `swift test --disable-keychain -j 2`. Add `ITDA_MODEL=<gguf>` for the model tests, which otherwise skip.
- App: `scripts/build-app.sh`, output `build/Itda.app`.
- Private-window checks: `scripts/e2e.sh`, plus `--measure <gguf>`, `--flicker`, `--engine <gguf>`. `--ime` switches the system's input source and needs the user idle.
- Always pass `--disable-keychain`: without it the first SwiftPM download of llama.cpp can hang on keychain credentials.
- **`scripts/e2e.sh` takes the user's keyboard and cursor focus while it runs. Ask them first, every time.** A 60 s pause in typing doesn't mean they have stopped using the Mac. Unit tests and reviews don't take focus.
- The Mac has limited memory: run one heavy build or model at a time, and don't steal focus.
- `docs/icon/generate.sh` makes icon options, with Codex's image tool. `docs/icon/build.sh a` rebuilds `Resources/`.

## Where things are
- `ItdaCore`: pure logic, with no model or GUI. Test it here first.
- `ItdaEngine`: llama.cpp, pinned by URL and checksum in `Package.swift`.
- `ItdaApp`: Accessibility, key tap, panel, and the window (`Window.swift`). Swift 5 language mode, as state is confined by hand to one queue.
- The tag `bench-1` keeps the replay harness (`itda-replay`), removed from main. Don't move it.

## Traps
- Accessibility grants are pinned to the signing certificate. The Developer ID build can't use a grant made for an Apple Development build, and a relaunch silently loses it. To keep one, re-sign that copy with the granted certificate and check it with `codesign -v -R <csreq from TCC.db>`.
- Activity Monitor's per-app Memory hides what Metal wires, about the model's file size. Read `docs/measuring.md` before claiming a memory number.
- `Gate.threshold` is fitted for English, and no Korean threshold exists. Don't tune it on Korean.
- A delayed cleanup belongs to the input revision that scheduled it. A successful field read is not a successful display.
- ggml asserts if a model is still loaded at exit: the app must unload on quit.
- Automatic tests don't reach Chromium's composition or real Tab. After any change to accepting or reading, run `docs/live-test.md`.
