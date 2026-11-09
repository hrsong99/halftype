# Tab Motion setting: where it lives in General (2026-11-09)

John: "I don't like how it's part of a line and pushes the text on the left (and also the left text is too long); shouldn't it be in its own section or box or something?"

- `index.html`: round 1. A (today) to F, as the General pane is drawn, each preview on one shared clock; click to switch motions. Plus image ideas G, H, I.
- `options-frozen.png`: A, B, C and E at the moment just after a Tab.
- `today.png`: the General pane as shipped in d94e500, the reference for the image ideas.
- `images/`: G, H, I from Codex's image tool, with `gen.sh` (the prompt, with each direction in the call) and logs.

Recommendation: C, three picture tiles (macOS's Appearance pattern), laid out as G does it: tiles beside the title.

Pick: John chose C, "but slightly better looking/polished". Built as `MotionTile` in Window.swift: three tiles under the title at full width, each a white field with a hairline and soft shadow playing its own motion, an accent ring and medium-weight name on the chosen one. Tiles beside the title (G's layout) were tried and dropped: in the 720-wide window they crushed the title to "Tab Motio/n". `built/` has the General page at three window sizes.
