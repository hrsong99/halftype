"""Builds ../round2.html from the round-1 page's styles. Run from docs/design/logo: python3 round2/page.py"""
CARDS = {
    "start": [
        ("G", "Round 1 G", "The colours you liked: paper, ink and a coral caret.", "round2/G.png"),
        ("J", "Round 1 J", "The complexity you liked: two strokes joining. Its catch: it reads as the hyperlink icon.", "images/h.png"),
    ],
    "drawn": [
        ("L", "Woven loops", "Two rounded loops at ±45°, over and under at all four crossings. Joined, balanced, not a chain. Drawn from image idea Q. Recommended.", "round2/L.png"),
        ("M", "Woven loops on ink", "L reversed: paper and coral strands on today's ink blue. Keeps continuity with the shipping icon and sits better in a dark Dock.", "round2/M.png"),
        ("N", "Two hooks holding", "Two open hooks, each holding the other. Joined, but with no closed loop, so no chain. The simplest of the new ones; reads as an S at 16 px.", "round2/N.png"),
        ("O", "Braid", "Two strands crossing twice: ink over, then coral over. Says \"joined\" best; wide and short, so it fills the tile less.", "round2/O.png"),
        ("P", "Handwriting into a caret", "One ink stroke loops like handwriting, runs into a line, and a coral caret takes over. Closest to what the app does; reads as \"el\" at a glance.", "round2/P.png"),
    ],
    "images": [
        ("Q", "Woven knot", "The best image this round, and the source of L. Thicker ribbons and a soft shadow at the crossings: worth trying on L if it looks thin.", "images/r2a.png"),
        ("R", "Loop into caret", "The same idea as P, but small and off-centre. P is the cleaner version.", "images/r2b.png"),
        ("S", "Ring threaded by the caret", "A coral caret through an ink ring, with a little paper-fold depth. Strong, but it reads as Φ: take the fold, not the shape.", "images/r2c.png"),
        ("T", "Hooked links", "Back to a chain link. Skip.", "images/r2d.png"),
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
<title>Itda logo, round 2</title><style>{style}</style></head><body><main>
<h1>Itda logo, round 2</h1>
<p class="q">Round 1 picks: G's colours, J's complexity. John: <i>"I like G's brighter colors but it's still too oversimplified I think. J has some more complexity, which i like. let's take some more variants from there."</i></p>
<div class="rec"><b>My pick: L</b>, two loops woven over and under: two strands that join, in G's paper, ink and coral. It has J's complexity without J's chain-link reading, it's symmetric, and the weave still shows at 32 px. At 16 px it becomes a coloured knot, which is fine for a Dock icon. <b>M</b> is the same mark on ink, if it has to hold up in a dark Dock. <b>N</b> is the simplest new one that still has two parts holding each other.</div>
<h2>Where we started</h2>{grid("start")}
<h2>Drawn options (vector, ready to build)</h2>{grid("drawn")}
<h2>Image ideas (Codex's image tool, G and J as references)</h2>
<p class="q">Images, not builds: each note says what's worth taking into a drawn version.</p>{grid("images")}
</main></body></html>
'''
open("round2.html", "w").write(page)
