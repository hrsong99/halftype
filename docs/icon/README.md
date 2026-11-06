# The icon

Three options from Codex's built-in image tool. `generate.sh` sends `prompts.txt`; `build.sh` masks them onto the macOS icon grid and builds `Resources/`.

`option-a` is the icon: a caret, then what hasn't been typed yet, fading out.

- **a, chosen.** It draws what the app does, in any language. In [options-compared.png](options-compared.png), its bright bar on a dark ground is the only mark still crisp at 16 px.
- **b, ring, caret, faded ring.** Reads as `ㅇ|ㅇ` to a Korean eye and `O|O` to anyone else. The pale ground melts into a light window, and the faded ring is gone at 16 px.
- **c, 잇 with a faded ㅅ.** The best idea, and correct Hangul: the syllable isn't finished yet. But it says nothing to someone who doesn't read Korean, and it's mush at 16 px.

The menu-bar glyph, `menubar.svg`, is the same caret and tail drawn by hand, because a template image has to be black and alpha at exact pixel sizes.
