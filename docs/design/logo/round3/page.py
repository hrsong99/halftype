"""Builds ../round3.html from the round-1 page's styles. Run from docs/design/logo: python3 round3/page.py"""
CARDS = {
    "start": [
        ("I", "The app's new look", "From the window thread (dither-look option I): a halftone sky from powder blue to peach, white frosted glass, near-black text, grey ghost text. Round 3 uses these colours.", "images/app-look-I.png"),
    ],
    "drawn": [
        ("3A", "Caret, halftone suggestion", "Round 1's idea on a glossy paper tile: a near-black caret and the suggestion printed as blue-to-peach halftone, the window's sky in one bar. Balanced, and the dots blur into a soft gradient at 32 px.", "round3/U.png"),
        ("3B", "The window in miniature", "The halftone sky, a frosted field, typed text, the caret and a grey ghost word: the app's own screen as its icon. Ties best to the window; busiest at 16 px.", "round3/V.png"),
        ("3C", "Tab key with the suggestion on it", "A cream keycap on the sky, labelled with a caret and the ghost after it: the key that takes a suggestion. No other icon in the references uses a key. The vector version of 3I.", "round3/W.png"),
        ("3D", "Cursor-simple, black", "The same mark as 3A on a black tile, with the halftone suggestion glowing against it. Strongest in a dark Dock, and the plainest.", "round3/X.png"),
        ("3E", "Hand-drawn", "A wobbly marker I-beam and a pencil scribble of words not yet written, on the sky. The playful direction; the I-beam reads as a capital I.", "round3/Y.png"),
    ],
    "images": [
        ("3F", "Glossy paper tile", "iA Writer's lesson: a soft pearly tile, the caret, two halftone ghost words. The finish is what 3A should borrow; the image already has its own tile shape, so it looks inset here.", "images/r3a.png"),
        ("3G", "Frosted field on the sky", "Like 3B, but the field is too small to read below 64 px.", "images/r3b.png"),
        ("3H", "Tab keycap, ⇥", "A chunky, glossy Tab key with the tab arrow on the sky. Instantly says \"press Tab\", and it's the most finished icon of the round. Generic on its own: any keyboard app could use it.", "images/r3c.png"),
        ("3I", "Tab keycap, caret and ghost", "The same key labelled with a caret and grey ghost text: \"Tab takes the suggestion\" in one object, in the window's colours. My pick.", "images/r3d.png"),
        ("3J", "Handwriting", "A pen line running into grey cursive. Charming, but thin and small at Dock size.", "images/r3e.png"),
        ("3K", "잇, brush-written", "Correct Hangul: ㅇ and ㅣ in black ink, ㅅ pale like ghost text. The most personal and the most Korean; to others it's a lettering mark. At 16 px the pale ㅅ vanishes and it reads 이.", "images/r3f.png"),
        ("3L", "Cursor-simple, isometric", "A black prism and a pale ghost block, Cursor-like. Clean, but it reads as a bar chart.", "images/r3g.png"),
        ("3M", "Halftone on black", "Like 3D, but tiny in the tile. 3D is the cleaner version.", "images/r3h.png"),
    ],
}


def card(letter, name, note, src):
    at = lambda n: f'<img src="{src}" width="{n}" height="{n}" style="border-radius:{n * .224:.1f}px">'
    strip = "".join(at(n) for n in (64, 32, 16))
    return (f'<div class="card"><h3><b>{letter}</b>{name}</h3><img class="big" src="{src}" style="border-radius:22.4%">'
            f'<div class="strip l">{strip}</div><div class="strip d">{strip}</div><p class="note">{note}</p></div>')


grid = lambda key: '<div class="grid">' + "".join(card(*c) for c in CARDS[key]) + "</div>"
style = open("index.html").read().split("<style>")[1].split("</style>")[0]
page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Itda logo, round 3</title><style>{style}</style></head><body><main>
<h1>Itda logo, round 3</h1>
<p class="q">After the references: caret and ghost text done properly (1), the Tab key (2), plus playful hand-drawn and Cursor-simple takes, in the app's new look. John: <i>"you can go ahead with 1 and 2, but maybe a few more in the playful, hand-drawn/hand-written style of granola or the simple style of cursor; also, i have another thread that's updating the main look of the app screen, so it should go well with that too"</i></p>
<div class="rec"><b>My pick: 3I, the Tab key labelled with a caret and ghost text</b>, built as the vector 3C. It says the whole product in one object: the key you press to take the suggestion, with the suggestion on it. It sits on the window's halftone sky, so the icon and the app read as one, and it doesn't lean the way today's icon does. <b>3A/3F</b> is the quieter choice: today's caret idea, rebalanced and given iA Writer's finish. For a playful option, <b>3K</b> (brush-written 잇) has the most personality.</div>
<h2>Where we are: the app's new look</h2><div class="card" style="max-width:520px"><img src="images/app-look-I.png" style="width:100%;border-radius:10px"><p class="note">{CARDS["start"][0][2]}</p></div>
<h2>Drawn options (vector, ready to build)</h2>{grid("drawn")}
<h2>Image ideas (Codex's image tool, the app look as reference)</h2>
<p class="q">Images, not builds: each note says what's worth taking into a drawn version.</p>{grid("images")}
</main></body></html>
'''
open("round3.html", "w").write(page)
