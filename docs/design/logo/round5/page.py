"""Builds ../round5.html from the round-1 page's styles. Run from docs/design/logo: python3 round5/page.py [--abs DIR]
--abs DIR points images at DIR (200 px JPEG thumbnails, for T3's html_render) and prints the page instead."""
import sys

NAMES = [  # checked 2026-11-08: rdap.org for domains, the iTunes Search API for the App Store, a web search for products
    ("Halftype", "free", "none", "No product found."),
    ("Undertype", "free", "none", "No product found."),
    ("Quietype", "free", "none", "No product found."),
    ("Fewkeys", "free", "none", "No product found."),
    ("Inkahead", "free", "none", "No product found."),
    ("Typeless", "-", "-", "<b>Out:</b> a Mac AI dictation app, USPTO application 99669312 (classes 9 and 42)."),
    ("Prewrite", "free", "none", "<b>Out:</b> an existing story-writing web app."),
    ("Lesstype, Aftertype", "-", "iOS apps", "<b>Out:</b> both names already on the App Store."),
    ("Foretype, Pretype, Ghostkey, Tabwise, Ieum", "taken", "-", "<b>Out:</b> the .app domain is taken, or apps already use the name."),
]
CARDS = [
    ("5A", "Halftype: h", "Half black ink, half glass, split right where the name says. The name is the picture, which none of the others manage. The strongest icon, and it reads at 32 px. Recommended.", "images/r5a.png"),
    ("5B", "Undertype: u", "A black u with a glass u under it, the suggestion beneath your typing. Clever, but the double letter blurs to a smudge at 16 px.", "images/r5b.png"),
    ("5C", "Quietype: q", "A calm q whose tail trails into glass. Pretty, but it reads as \"a\" or \"9\" at a glance.", "images/r5c.png"),
    ("5D", "Fewkeys: f", "A cursive f written from one glass keycap. It brings back 4C's key, but the f is thin and the key is tiny.", "images/r5d.png"),
    ("5E", "Inkahead: i", "An i whose dot has run ahead as a glass drop. A nice story, but it reads as a \"c\" or a tick.", "images/r5e.png"),
    ("5F", "Halftype, the whole word", "The full name as a ribbon: \"half\" in ink, \"type\" in glass. It works as a wordmark for the website and About window, not as an icon: at 32 px it's a line.", "images/r5f.png"),
]


def card(letter, name, note, src):
    at = lambda n: f'<img src="{src}" width="{n}" height="{n}" style="border-radius:{n * .224:.1f}px">'
    strip = "".join(at(n) for n in (64, 32, 16))
    return (f'<div class="card"><h3><b>{letter}</b>{name}</h3><img class="big" src="{src}" style="border-radius:22.4%">'
            f'<div class="strip l">{strip}</div><div class="strip d">{strip}</div><p class="note">{note}</p></div>')


absdir = sys.argv[sys.argv.index("--abs") + 1] if "--abs" in sys.argv else None
if absdir:
    CARDS = [(a, b, c, f"{absdir}/{d.split('/')[-1][:-4]}.jpg") for a, b, c, d in CARDS]
rows = "".join(f"<tr><td><b>{n}</b></td><td>{d}</td><td>{s}</td><td>{w}</td></tr>" for n, d, s, w in NAMES)
style = open("index.html").read().split("<style>")[1].split("</style>")[0]
page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Itda logo, round 5</title><style>{style}
table{{border-collapse:collapse;font-size:13.5px;margin:6px 0 4px}}td{{padding:5px 10px 5px 0;border-bottom:1px solid var(--border,#ddd);vertical-align:top}}</style></head><body><main>
<h1>Itda logo, round 5: names</h1>
<p class="q">John: <i>"Can we use the name typeless, or would there be a legal problem with that? If not, can I see some versions with that name in mind"</i>. Typeless is taken, so these are 4E, subtly coloured, for names that passed a first check.</p>
<div class="rec"><b>My pick: Halftype (5A).</b> The name says what the app does (you type half, it writes the rest), and the icon draws it: a cursive h, half ink, half glass. It's the only pair where the name and the picture are the same idea. Use 5F as the wordmark beside it. Before you commit to it, pay for a proper trademark search (USPTO and KIPO): mine was only a first pass.</div>
<h2>Name check</h2>
<table><tr><td><b>Name</b></td><td>.app domain</td><td>App Store</td><td>Web</td></tr>{rows}</table>
<p class="q">Every short .com is taken (parked), so plan on .app or get-&lt;name&gt;.com.</p>
<h2>Icons (Codex's image tool, 4E as the reference)</h2>
<div class="grid">{"".join(card(*c) for c in CARDS)}</div>
</main></body></html>
'''
if absdir:
    print(page)
else:
    open("round5.html", "w").write(page)
