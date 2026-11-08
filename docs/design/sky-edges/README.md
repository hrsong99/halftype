# Sky edges (round 1)

Question: the window's halftone sky. Is the trouble that its edges stop too abruptly, or that the middle is too empty?
John: "the edges of the pixel art kind of end too abruptly, or the middle feels too empty? Not sure which, show me some variants"

- `index.html`: the options. A–G are drawn from a canvas port of `Sky.metal`'s `ink()` at rest (no typing), with a dark/light toggle. H–J are Codex image ideas.
- `options.png`: a frozen screenshot of the page (dark).
- `images/`: `today.png` (John's screenshot, passed to Codex), `H/I/J.png`, `prompts/`, and `gen.sh <letter>` to remake one.

Recommendation: B (soft taper), maybe with F (curved horizon). Pick: (pending)

## Round 2: B + subtle F, and B + C

John: "Show me B + (subtle) F and B + C"

- `round2.html`: A today, B alone, C B + 30 pt arc, D B + 50 pt arc, E B + gentle C (±8 pt wander, dot-size grain in the taper), F B + C (±16 pt, grain, spatter up to 24 pt past the edge). "Writing" toggles the risen horizon; `round2.html#writing` opens on it.
- `round2.png`: frozen screenshot, at rest, dark.
- C's first try dropped faint dots at random, which threw away B's taper and made the edge hard again; varying dot size instead keeps it soft.

Recommendation: C. Pick (John, 2026-11-08): C, "Sure I guess C is okay". Not built yet: John moved on to the home page's look (`../home-glass/`) first.
