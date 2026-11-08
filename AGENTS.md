# Halftype (formerly Itda): what a future agent must know

A menu-bar Mac app: inline Korean and English suggestions from a local model. Read `docs/how-it-works.md` first.

## Must not break
- **No private text, ever.** Nothing from anyone's messages goes in this repo: not tests, docs, commit messages or screenshots. Test strings are invented, and benchmark results are aggregates only. Replay traces hold typed text and stay out.
- **Privacy claims in the README are promises.** No network except `ModelStore`'s model URLs and Sparkle's update feed, no typed text written to disk or logs, no Screen Recording, secure fields skipped. A change that touches one changes the README in the same commit.
- **Licences.** AGPL, GPL and unlicensed projects in `CREDITS.md` gave ideas only. No code from them. A new borrowed idea gets a row there, with its licence checked.
- **Every number carries how it was measured**, here or in `docs/measuring.md`. Remeasure rather than edit one by hand.

## Commands
- Tests: `swift test --disable-keychain -j 2`. Add `HALFTYPE_MODEL=<gguf>` for the model tests, which otherwise skip.
- App: `scripts/build-app.sh`, output `build/Halftype.app`. Renamed from Itda on 2026-11-08, everywhere: bundle ID `app.halftype.Halftype`, modules, repo `hrsong99/halftype`, cask `halftype`. `moveFromItda` carries the old folder and settings over once. Checkouts are `halftype` and `halftype-learn`, the lab `~/halftype-lab-private`, signing `~/.config/halftype-signing` and the `halftype-signing` keychain; `itda*` symlinks to them stay for old T3 history. Only the tag `bench-1`'s `itda-replay` keeps the old name.
- Private-window checks: `scripts/e2e.sh`, plus `--races` (30 s, for one failing check), `--measure <gguf>`, `--flicker`, `--engine <gguf>`. `--ime` switches the system's input source and needs the user idle.
- Window PNGs with no focus taken: `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots`. Off-screen shots leave out the window's blurred ribbon (a SwiftUI Canvas); judge it from `15` (the whole window at three sizes, by ImageRenderer, which draws the text field as a yellow block). Glass suggestions, as drawn over our own field: `halftype-e2e --shots <dir>` (`glass`, `glass-wrap`).
- Always pass `--disable-keychain`: without it the first SwiftPM download of llama.cpp can hang on keychain credentials.
- **`scripts/e2e.sh` takes the user's keyboard and cursor focus while it runs. Ask them first, every time.** A 60 s pause in typing doesn't mean they have stopped using the Mac. Unit tests and reviews don't take focus.
- The Mac has limited memory: run one heavy build or model at a time, and don't steal focus.
- `docs/icon/generate.sh` makes icon options, with Codex's image tool. `docs/icon/build.sh d` rebuilds `Resources/`. The window's `Mark` (Window.swift) draws `docs/icon/menubar.svg`'s paths by hand: change the logo, change it too.

## Where things are
- `HalftypeCore`: pure logic, with no model or GUI. Test it here first.
- `HalftypeEngine`: llama.cpp, pinned by URL and checksum in `Package.swift`.
- `HalftypeApp`: Accessibility, key tap, panel, and the window (`Window.swift`). Swift 5 language mode, as state is confined by hand to one queue.
- The tag `bench-1` keeps the replay harness (`itda-replay`), removed from main. Don't move it.
- Learning from use: branch `learn`, `lab/PLAYBOOK.md`. Only a per-user LoRA moved keys saved; prompt, logit and gate methods were ~0. Judge any prompt change against the screen-context baseline there.
- Personal model: the last `*.gguf` by name in `~/Library/Application Support/Halftype/adapters/<model file>/`, for that model only (from `lab/dogfood/train.sh` on `learn`), shows General > Personal Model. Compare leaves it off on even dates, and Stats sets the two kinds of day side by side.
- The local branch `bench-2` (worktree `../local-autocomplete/bench2-worktree`) replays the shipped policy; the 2026-11 numbers in `docs/measuring.md` come from it, run by `../local-autocomplete/experiments/bench2/run.sh` and scored by `report.py` there.

## Traps
- Accessibility grants are pinned to the signing certificate. The Developer ID build can't use a grant made for an Apple Development build, and a relaunch silently loses it. To keep one, re-sign that copy with the granted certificate and check it with `codesign -v -R <csreq from TCC.db>`.
- Activity Monitor's per-app Memory hides what Metal wires, about the model's file size. Read `docs/measuring.md` before claiming a memory number.
- `Gate.threshold` is fitted for English, and no Korean threshold exists. Don't tune it on Korean.
- A delayed cleanup belongs to the input revision that scheduled it. A successful field read is not a successful display.
- AX on our own window (Try It) is answered in-process on the asking thread, and SwiftUI crashes off main. Read through `AX.get`, which hops to main for our pid (`AX.own`); a test that blocks main must not wait on the watcher.
- ggml asserts if a model is still loaded at exit: the app must unload on quit.
- Automatic tests don't reach Chromium's composition or real Tab. After any change to accepting or reading, run `docs/live-test.md`.
- An agent can run most of `docs/live-test.md` itself while the user is away: start `build/<app>/Contents/MacOS/Halftype` from the shell (it inherits the terminal's Accessibility; a newly signed build's own grant needs Touch ID), bring the host app forward, type with `scripts/live-keys.swift`, and `screencapture -x` the screen. Not codex-cu: it drives apps in the background, Halftype follows the frontmost one, its window shots miss the ghost panel, and a stuck `SkyComputerUseService` doubles every key (`pkill -f SkyComputerUseService`).
