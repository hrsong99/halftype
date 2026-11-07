# Logo, round 1

The question: what should Itda's app icon be? John: "the current one is nice but not balanced enough."

The shipping icon (`docs/icon/option-a`) leans left: the solid caret holds the weight 22% in from the left, and the bar meant to balance it fades to nothing.

- `index.html`: the options. A is today; B–H are drawn as SVG in the page, ready to build; I–K are Codex image-tool takes.
- `options.png`: a frozen screenshot of all of them.
- `prompts.txt`, `gen.sh`: the image prompts and the script that made `images/g|h|i-raw.png` (with today's icon as reference).
- `images/`: today's tile and the generated images, resized for the page.

Recommended: C, the caret on the centre line between solid typed text and a ghost suggestion.

Pick: none outright; round 2 builds on G's colours and J's complexity.

## Round 2

John: "I like G's brighter colors but it's still too oversimplified I think. J has some more complexity, which i like. let's take some more variants from there."

- `round2.html`, `round2.png`: G and J as the starting point, five drawn options (L–P) and four image ideas (Q–T).
- `round2/make.py` writes the drawn SVGs (`round2/L.svg`…); `round2/page.py` builds the page. Woven crossings use masks, not clips over a paper underlay: a clip edge across a strand leaves a seam.
- `prompts-round2.txt`, `gen-round2.sh`: the image prompts, with `images/G-ref.png` and `images/h.png` as references.

Recommended: L, two loops woven over and under, in paper, ink and coral.

Pick: not yet.
