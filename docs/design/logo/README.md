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

## References

John, after round 2: "doesn't really give off the feeling of being a text completion tool. Can you give me some references for icons of well designed saas software and such?"

- `references.html`: 24 shipping icons (writing tools, voice and AI tools, Mac SaaS), each with how it says its job, and a TL;DR.
- `references/fetch.py` downloads the icons from the iTunes Search API and the makers' sites; they are trademarks, so they stay gitignored. Run it before opening the page.

## Round 3

John, after the references: "you can go ahead with 1 and 2, but maybe a few more in the playful, hand-drawn/hand-written style of granola or the simple style of cursor; also, i have another thread that's updating the main look of the app screen, so it should go well with that too"

The window thread picked dither-look option I (a light halftone sky, powder blue to peach, white frosted glass), so round 3 uses those colours; `images/app-look-I.png` is that window.

- `round3.html`: drawn 3A–3E (`round3/make.py` writes `U V W X Y .svg/.png`, the halftone dots generated in code), image ideas 3F–3M (`images/r3a`–`r3h`).
- `round3.png`: the thirteen icons in one sheet (file names, not letters: U–Y are 3A–3E, r3a–r3h are 3F–3M).
- `prompts-round3.txt`, `gen-round3.sh`: the image prompts, with the window as reference.

Recommended: 3I, a Tab keycap labelled with a caret and ghost text, built as the vector 3C. Whichever wins also replaces the caret mark above the field in the window.

Pick: not yet.

## Round 4

John: "i really want to move away from the caret and line motif, and i honestly think i'm going to change the name of the app so no need to be hung up on that. If i had to say, 3e, 3h, 3j, and 3l look the best (all different styles, I know)"

So: no caret and line, no letters or name. Eight image-tool takes on 3E (hand-drawn), 3H (keycap), 3J (handwriting) and 3L (isometric), alone and crossed, each with its sources as references.

- `round4.html`, `round4.png`: the eight (4A–4H). `round4/page.py` builds the page from `round4/notes.py`.
- `prompts-round4.txt`, `gen-round4.sh`: the prompts and which reference images each one got.

Recommended: 4H, the risograph Tab key; 4C (doodled key) for looser, 4B (black key, glass key) for minimal. Whichever wins gets re-centred and drawn as a vector.

Pick: not yet.
