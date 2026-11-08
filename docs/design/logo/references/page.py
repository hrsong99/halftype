"""Builds ../references.html from the icons fetch.py saved. Run from this folder: python3 page.py [--abs]
--abs writes absolute image paths (for T3's html_render) to stdout instead."""
import json, sys
from pathlib import Path

here = Path(__file__).parent
found = json.loads((here / "found.json").read_text())

GROUPS = [
    ("Typing and writing tools: the closest neighbours", [
        ("cotypist", "The direct competitor: inline completions on the Mac. A mascot holding a text cursor, so it says \"typing helper\" at once, though the robot is busy at 16 px."),
        ("iawriter", "One cyan caret on a white tile. As simple as our A, and it works: the caret is the whole message, and the glossy white tile makes it feel like a page."),
        ("grammarly", "A letter G inside a speech-bubble shape. Says \"writing\" by using a letter."),
        ("textexpander", "A lowercase t with a little flag: a letter in motion, so it reads as text that expands."),
        ("drafts", "A blank page with its corner peeled. A writing object, rendered with depth."),
        ("bear", "A mascot, no text metaphor at all. The colour carries the brand."),
        ("ulysses", "A butterfly with a pen nib for a body: a symbol, with one writing detail hidden in it."),
    ]),
    ("Voice and AI tools", [
        ("wispr", "Bars like a sound wave. Literal for voice, in black and white."),
        ("superwhisper", "An abstract rounded triangle in glossy black. Says \"premium\" rather than \"dictation\"."),
        ("claude", "A coral starburst. A brand mark, not a picture of the job."),
        ("chatgpt", "An interlaced knot, the same family as our round-2 L. That's why L felt like \"an AI brand\", not \"a typing tool\"."),
        ("perplexity", "A geometric line drawing, abstract."),
        ("granola", "A spiral on lime: playful, ownable, not literal."),
        ("cursor", "A black 3D cube on cream: abstract, and the dimension does the work."),
        ("notion", "A letter N on a paper block: letter plus object."),
    ]),
    ("Well-crafted SaaS for the Mac", [
        ("things", "A checkbox rendered as a physical object. The job, made tactile."),
        ("fantastical", "A calendar page, literal, with a little colour."),
        ("superhuman", "An envelope with light and depth."),
        ("mimestream", "An envelope too: same object, own colours."),
        ("craft", "Four soft shapes as a grid of blocks: abstract, but it hints at documents."),
        ("linear", "A circle cut by lines: abstract, monochrome, precise."),
        ("raycast", "A bold geometric mark on a dark tile."),
        ("cleanshot", "A screenshot frame on a dark tile: the tool's own object."),
        ("arc", "A loose hand-drawn A: a letter, but with personality."),
    ]),
]


def card(name, note, prefix):
    meta = found.get(name)
    if not meta:
        return ""
    # App Store iOS icons are full-bleed squares; Mac and web icons carry their own shape.
    radius = "22.4%" if meta["platform"] == "ios" else "0"
    return (f'<div class="ref"><img src="{prefix}{name}.png" style="border-radius:{radius}" alt="">'
            f'<div><b>{meta["app"]}</b><p>{note}</p></div></div>')


def page(prefix):
    groups = "".join(f'<h2>{title}</h2><div class="refs">{"".join(card(n, t, prefix) for n, t in items)}</div>'
                     for title, items in GROUPS)
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Itda logo references</title><style>
*{{box-sizing:border-box}}body{{margin:0;font:15px/1.5 var(--font-sans,-apple-system,system-ui,sans-serif)}}
h2{{font-size:16px;margin:26px 0 12px}}.q{{opacity:.7;margin:0 0 14px}}
.tldr{{border:1px solid var(--border,#ddd);background:var(--card,transparent);border-radius:var(--radius,12px);padding:14px 16px}}.tldr ol{{margin:6px 0 0;padding-left:20px}}.tldr li{{margin:4px 0}}
.refs{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px}}
.ref{{display:flex;gap:14px;align-items:flex-start;border:1px solid var(--border,#ddd);background:var(--card,transparent);border-radius:var(--radius,12px);padding:12px}}
.ref img{{width:72px;height:72px;flex:none}}.ref b{{font-size:14px}}.ref p{{margin:2px 0 0;font-size:13.5px;opacity:.75}}
</style></head><body>
<p class="q">John, after round 2: <i>"doesn't really give off the feeling of being a text completion tool. Can you give me some references for icons of well designed saas software and such?"</i> Icons as their makers ship them, from the App Store or their own sites.</p>
<div class="tldr"><b>TL;DR: icons that say "text" use a caret, a letter, or a writing object. The knots say "brand".</b><ol>
<li><b>Round 2 lost the caret, and that's why it stopped feeling like typing.</b> The woven loops sit in the same family as ChatGPT's knot. Every tool here that reads as "writing" keeps a caret (iA Writer, Cotypist), a letter (Grammarly, TextExpander, Notion), or a page (Drafts, Fantastical).</li>
<li><b>A simple mark can work: iA Writer is just a caret.</b> What carries it is the finish. A white glossy tile reads as a page, and the caret has light and depth. Our A was flat on a dark tile, which reads as a terminal.</li>
<li><b>The craft is in the material.</b> Things, Superhuman, Drafts and Cursor all render one object with light, depth and a soft shadow, in the macOS 26 style. None of our drawn options did that.</li>
<li><b>Cotypist, the direct competitor, uses a mascot holding a caret.</b> Being "the one without a robot" is a clear way to stand apart.</li>
</ol>
<p style="margin:10px 0 0"><b>For round 3, I suggest:</b> (a) iA Writer's lesson, our caret and ghost text on a glossy paper tile in G's colours, rendered with depth; (b) a <b>Tab keycap</b> with grey suggestion text on it, because Tab is how you take a suggestion and no other icon here uses it; (c) a letter: 잇 or "it" with the last stroke as ghost text.</p></div>
{groups}
</body></html>
'''


if "--abs" in sys.argv:
    print(page(f"{here.resolve()}/"))
else:
    (here.parent / "references.html").write_text(page("references/"))
