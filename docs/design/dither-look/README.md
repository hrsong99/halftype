# The dithered look (round 1)

Question: should Itda's window take the look of Jon Kelley's Devin redesign (dark, dithered pixel backdrop, frosted glass)?
Reference: https://x.com/jkelleyrtp/status/2118843865415463348
John: "I kinda like how this looks, can you show me some variants of our app looking like that."

- `index.html`: the options. A–F are drawn in HTML (canvas Bayer dither + CSS glass); G–I are Codex image ideas.
- `options.png`: frozen screenshot of the page.
- `images/`: `today.png` (reference passed to Codex), `G/H/I.png`, `prompts/`, `gen.sh <letter>` to remake one.

Recommendation: D (dither as a glow behind the field only), or B for the full Devin feel.

Pick: I (round 2).

## Round 2: I, moving

John: "I like I, maybe with some animation/movement when I'm typing and esp when I'm accepting."

- `round2.html`: six motions on I's halftone sky (A still, B ripples, C printed in, D sun comes up, E drifting sky, F only on Tab), on one shared clock, plus a box to type into that drives all six. `round2.html#t=4.05` freezes the clock at that second.
- `round2.png`: frozen at 4.05 s, just after the first Tab.

Recommendation: C. Pick: (pending)

## Round 3: D with a bit of F

John: "Can I see a version of D and a little bit of F? F as in the biggest animation is on tab, that of D, but subtler (and typing has an extremely subtle and quick ripple, one that dies down very quick so typing fast never invades into the tab instructions)."

- `round3.html`: A rise and swell, B still sky with swell on Tab, C warmth spreading from the words; round 2's D and F as D′ and F′. The key ripple is drawn above the glass (behind it, the blur erased it), lasts 0.3 s, and fast typing takes the strongest ripple rather than adding them up.
- `round3.png`: frozen at 4.25 s, just after the first Tab.

Recommendation: A. Pick: (pending)
