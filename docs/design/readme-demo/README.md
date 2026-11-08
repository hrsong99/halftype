# README demo: how the README shows Halftype at work

John, 2026-11-08, on the README's two GIFs (a plain white box with text): "this part doesn't look good; look at competitors and get some ideas for how to make this nice looking and polished, even if we have to add 'Tab' icons or animations or something".

- `index.html`: round 1. Options A–F animate on one shared clock (Replay, Slow ×0.5); G–I are Codex image-tool ideas.
- `round1-screenshot.png`: the page frozen. It was captured before D–F got their styles, so those three look plain in it; the page itself is right.
- `images/today.png`: what the README showed. `images/G.jpg`, `H.jpg`, `I.jpg`: generated, prompts in `prompts.txt` (made with `today.png` as reference).

Competitors looked at: Cotabby (open source) records real apps and puts a small "Tab" pill after the grey text; Cotypist's site has no demo, only "Press ⇥ Tab to accept" in text.

Recommendation: B (a compose window on the app's dot sky, with a keycap that dips on each Tab), with C's chip as a hint on the first sentence. Built from the same real-model frames `scripts/demo.sh` makes today.

Pick: John picked F, English only for now, and asked for a stronger example than finishing the last word of a long sentence. Built in `scripts/demo.sh` and `--demo` in Tests/e2e: a real replay with the default model, Tab wherever the grey text is what comes next, so each sentence shows about half its keys saved. Output: `docs/media/demo.gif`.

## Round 2: timing

John, on the glass demo with rapid Tabs (A): "Yikes that looks messy. Give me some variants of different timings and stuff".

- `round2.html`: seven real renders (`round2/A–G.webp`) from `scripts/demo.sh` with `HALFTYPE_DEMO_PACE` set (in `Tests/e2e/E2E.swift`: type, tab, beat, after in hundredths; glint word, burst or none; key 0 or 1). "Replay all together" restarts them at once.
- `round2.png`: one frame of each.
- B–G also keep a suggestion while the typing matches it, as the app does; A asked the model again after every letter, so suggestions jumped.

Recommendation: D (`beat=12,tab=14,after=8,glint=burst`).

## Round 3: Tab and Shift-Tab

John: "What if we mix tabs and shift tabs? So show using tab for some small suggestions, and then shift tab (after a pause) to show accepting a long suggestion?"

- `round3.html`: D from round 2 for comparison, and H, I, J (`round3/*.webp`): on D's timing, a fresh suggestion of `long` words or more that is right to the end gets a `hold`, then Shift-Tab and one glint across it (`HALFTYPE_DEMO_PACE` gains `long` and `hold`; the shift key shows when `long` is set).
- `round3.png`: one frame of each.

Recommendation: H (`beat=12,tab=14,after=8,glint=burst,long=3,hold=40`).
