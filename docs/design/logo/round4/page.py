"""Builds ../round4.html from the round-1 page's styles. Run from docs/design/logo: python3 round4/page.py"""
from notes import NOTES, RECOMMENDATION

CARDS = {
    "start": [
        ("3E", "Hand-drawn", "Marker doodle on the halftone sky.", "round3/Y.png"),
        ("3H", "Tab keycap", "A glossy physical key.", "images/r3c.png"),
        ("3J", "Handwriting", "A pen line running into grey cursive.", "images/r3e.png"),
        ("3L", "Isometric", "Matte black and pale glass, Cursor-simple.", "images/r3g.png"),
    ],
    "images": NOTES,
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
<title>Itda logo, round 4</title><style>{style}</style></head><body><main>
<h1>Itda logo, round 4</h1>
<p class="q">No caret and line, no name or letters (the app may be renamed). Built from the four you liked, alone and crossed. John: <i>"i really want to move away from the caret and line motif, and i honestly think i'm going to change the name of the app so no need to be hung up on that. If i had to say, 3e, 3h, 3j, and 3l look the best (all different styles, I know)"</i></p>
<div class="rec">{RECOMMENDATION}</div>
<h2>What you liked in round 3</h2>{grid("start")}
<h2>Round 4 (Codex's image tool, the four above as references)</h2>
<p class="q">Images, not builds: the pick gets drawn as a vector afterwards.</p>{grid("images")}
</main></body></html>
'''
open("round4.html", "w").write(page)
