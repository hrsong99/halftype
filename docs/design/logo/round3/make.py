"""Writes the round-3 drawn logo options as SVG (100-unit tile) and PNG. Colours follow the app's new look
(docs/design/dither-look, option I): a halftone sky from powder blue to peach on paper, near-black text, grey ghost text.
Run: python3 make.py"""
import math, subprocess
from pathlib import Path

PAPER, INK, GHOST = "#FBF7F1", "#17181C", "#A9ABB1"
BLUE, PEACH = (127, 195, 236), (244, 169, 138)
here = Path(__file__).parent


def mix(a, b, t):
    return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def sky(step=3.4, rmax=1.55, strength=1.0):
    """The app's halftone sky as dots on a 45° grid: blue dots at the top, peach at the bottom, bare paper in between."""
    dots = []
    for i in range(-40, 41):
        for j in range(-40, 41):
            x, y = 50 + (i - j) * step / 2, 50 + (i + j) * step / 2
            if not (-2 < x < 102 and -2 < y < 102):
                continue
            t = y / 100
            blue, peach = max(0, 1 - t / .55), max(0, (t - .45) / .55)
            s = max(blue, peach) * strength
            if s > .04:
                dots.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{rmax * math.sqrt(s):.2f}" fill="{mix(BLUE, PEACH, t)}"/>')
    return "".join(dots)


def halftone_bar(x0, y0, w, h, step=2.6, r=1.25):
    """A ghost-text bar made of dots, blue fading into peach along its length."""
    dots = [f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r * (1 - .3 * (x - x0) / w):.2f}" fill="{mix(BLUE, PEACH, (x - x0) / w)}"/>'
            for k in range(int(w / step) + 1) for m in range(int(h / step) + 1)
            for x, y in [(x0 + k * step + (m % 2) * step / 2, y0 + m * step + step / 2)] if x < x0 + w]
    return f'<g clip-path="url(#bar{x0:.0f})">{"".join(dots)}</g>', f'<clipPath id="bar{x0:.0f}"><rect x="{x0}" y="{y0}" width="{w}" height="{h}" rx="{h / 2}"/></clipPath>'


def tile(body, defs="", bg=PAPER):
    gloss = ('<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".55"/>'
             '<stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>'
             '<clipPath id="sq"><rect width="100" height="100" rx="22.4"/></clipPath>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs>{gloss}{defs}</defs>'
            f'<g clip-path="url(#sq)"><rect width="100" height="100" fill="{bg}"/>{body}</g></svg>')


bars = [halftone_bar(46, 43, 32, 14)]
shadow = '<filter id="sh" x="-30%" y="-30%" width="160%" height="180%"><feDropShadow dx="0" dy="1.6" stdDeviation="1.8" flood-color="#2b2a33" flood-opacity=".22"/></filter>'

options = {
    # U: iA Writer's lesson in our colours: a glossy paper tile, the caret, and the suggestion printed in halftone.
    "U": tile('<rect width="100" height="100" fill="url(#gloss)"/>'
              f'<rect x="27" y="27" width="10" height="46" rx="5" fill="{INK}" filter="url(#sh)"/>'
              + "".join(b[0] for b in bars),
              shadow + "".join(b[1] for b in bars)),
    # V: the app window in miniature: the halftone sky, a frosted field, the caret and a grey ghost word.
    "V": tile(sky() + f'<rect x="14" y="38" width="72" height="24" rx="12" fill="#fff" fill-opacity=".82" stroke="#fff" stroke-width=".8" filter="url(#sh)"/>'
              f'<rect x="24" y="43" width="16" height="14" rx="4" fill="{INK}" opacity="0"/>'
              f'<rect x="24" y="45" width="18" height="10" rx="5" fill="{INK}"/><rect x="45" y="41" width="3.6" height="18" rx="1.8" fill="{INK}"/>'
              f'<rect x="52" y="45" width="24" height="10" rx="5" fill="{GHOST}"/>', shadow),
    # W: the Tab key, labelled with what it does: a caret and the ghost after it.
    "W": tile(sky(strength=.8)
              + '<rect x="14" y="27" width="72" height="50" rx="13" fill="#d9d3cb" filter="url(#sh)"/>'
              + '<rect x="14" y="24" width="72" height="49" rx="13" fill="url(#key)"/>'
              + '<rect x="19" y="27" width="62" height="40" rx="10" fill="url(#top)"/>'
              + f'<rect x="32" y="37" width="6" height="20" rx="3" fill="{INK}"/><rect x="42" y="44" width="26" height="6" rx="3" fill="{GHOST}"/>',
              shadow + '<linearGradient id="key" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fffdf9"/><stop offset="1" stop-color="#ebe6de"/></linearGradient>'
              '<linearGradient id="top" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbf9f5"/><stop offset="1" stop-color="#fffefc"/></linearGradient>'),
    # X: Cursor-simple: black tile, a white caret, the suggestion dissolving in as halftone.
    "X": tile(f'<rect x="27" y="27" width="10" height="46" rx="5" fill="#fff"/>' + "".join(b[0] for b in bars),
              "".join(b[1] for b in bars), bg="#121316"),
    # Y: hand-drawn: a wobbly marker caret and a pencil scribble of words not yet written, on the sky.
    "Y": tile(sky(strength=.7)
              + '<g filter="url(#wob)" fill="none" stroke-linecap="round" stroke-linejoin="round">'
              f'<path d="M33 27 C34 40 32 58 33.5 73 M27 27.5 C30 26.5 36 27 39 27.8 M27.5 73 C31 72.4 35 73.3 39.5 72.6" stroke="{INK}" stroke-width="5"/>'
              f'<path d="M45 56 C49 46 52 46 53 53 C54 60 57 60 59 51 C61 44 63 47 64 54 C65 60 68 59 70 52 C71.5 47 74 47 75 53 C76 58 79 57 81 53" stroke="#8d9097" stroke-width="3.2" stroke-opacity=".8"/></g>',
              '<filter id="wob"><feTurbulence type="fractalNoise" baseFrequency=".09" numOctaves="2" seed="4"/><feDisplacementMap in="SourceGraphic" scale="2.4"/></filter>'),
}

for name, svg in options.items():
    (here / f"{name}.svg").write_text(svg)
    subprocess.run(["rsvg-convert", "-w", "512", "-h", "512", here / f"{name}.svg", "-o", here / f"{name}.png"], check=True)
