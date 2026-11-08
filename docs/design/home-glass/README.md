# The home window, in the icon's materials (round 1)

Question: should the home (field) window take its look from the new icon (logo 5A, `docs/icon/option-d.png`: a cursive h, glossy ink stem, frosted-glass arch going pale blue to peach, on cream)?
John: "we recently came up with a new, glassy icon for halftype right? Can you show me some variants of the home page that takes inspiration from the icon style?"

- `index.html`: A today (with sky-edges C), B cream and ink, C half ink and half glass (the suggestion drawn in glass), D a blurred glass ribbon behind, E ink window and glass field, F sky on cream with a glass field, G the icon art as hero. H–J are Codex image ideas.
- `options.png`: frozen screenshot of the page.
- `images/`: `icon.png` and `today.png` (the references passed to Codex), `H/I/J.png`, `prompts/`, `gen.sh <letter>` to remake one.

Recommendation: C, with H's stronger glass colours and its glossy h. Pick: John asked for C + D (round 2).

## Round 2: C + D, and a gleam

John: "What about C + D (and can we make the suggestions gleam like that)"

- `round2.html`: five C + D windows on one 6 s clock (suggestion at 0.5 s, Tab at 3.8 s turns the glass to ink), with pause, replay, ½× and ¼×, and a scrubber; `round2.html#t=0.95` freezes it. A sweep (one glint on arrival, one on Tab), B flowing glass, C written in, D a sharper glass ribbon, E a faint ribbon. F and G are Codex images (`images/K.png`, `L.png`).
- `round2.png`: frozen at 0.95 s, A mid-glint and C mid-write.

Recommendation: A (sweep); ribbon D or E.

John (after round 2): "because suggestions change so often we don't want there to be an animation when the suggestions appear right? They should just appear instantaneously with the glassy look, but when accepted they should sweep or something very quickly". So: C + D, suggestions in glass with no entrance, one quick glint on Tab only.

Pick (John, 2026-11-08), with the recommended answers: the soft ribbon (round 2's A–C), a 0.25 s glint, cream in dark mode too, upright (not italic) suggestions. Built on main: the window draws the icon's cream with the blurred arch on the field page (`Backdrop` in `Window.swift`), the field glints on a Tab taken here (`Glint`), and the ghost overlay paints a suggestion in our own field blue to peach in reading order (`GhostView`). The halftone sky (`Sky.swift`, `Sky.metal`) is gone. `built/window/` and `built/ghost/` are the shots: `15-window-*.png` and `glass*.png`.
