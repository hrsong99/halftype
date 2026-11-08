"""Writes the round-2 drawn logo options as SVGs on a 100-unit tile. Run: python3 make.py"""
from pathlib import Path

PAPER, INK, CORAL = "#F4EFE6", "#14213D", "#F26B4F"
W, GAP = 9, 15  # stroke width; the gap a strand leaves where another passes over it


def tile(bg, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs>{defs}</defs>'
            f'<rect width="100" height="100" rx="22.4" fill="{bg}"/>'
            f'<g fill="none" stroke-width="{W}" stroke-linecap="round">{body}</g></svg>')


def weave(bg, ca, cb, a, b, a_over, b_over):
    """Two strands (SVG shape tags without stroke). Each is cut by a band of the other only
    inside the circles where the other is on top, so no clip edge ever crosses a visible strand."""
    circles = lambda pts: "".join(f'<circle cx="{x}" cy="{y}" r="10"/>' for x, y in pts)
    band = lambda shape: shape.replace("/>", f' stroke="#000" stroke-width="{GAP}" fill="none"/>')
    mask = lambda mid, clip, shape: (f'<mask id="{mid}" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">'
                                     f'<rect width="100" height="100" fill="#fff"/><g clip-path="url(#{clip})">{band(shape)}</g></mask>')
    defs = (f'<clipPath id="ca">{circles(a_over)}</clipPath><clipPath id="cb">{circles(b_over)}</clipPath>'
            + mask("ma", "cb", b) + mask("mb", "ca", a))
    body = (f'<g mask="url(#ma)">{a.replace("/>", f" stroke=\"{ca}\"/>")}</g>'
            f'<g mask="url(#mb)">{b.replace("/>", f" stroke=\"{cb}\"/>")}</g>')
    return tile(bg, body, defs)


# L: two rounded loops at ±45°, over and under at their four crossings (drawn from image idea Q).
KA = '<rect x="22" y="38" width="56" height="24" rx="12" transform="rotate(45 50 50)"/>'
KB = '<rect x="22" y="38" width="56" height="24" rx="12" transform="rotate(-45 50 50)"/>'
K_A_OVER, K_B_OVER = [(50, 33), (50, 67)], [(33, 50), (67, 50)]

options = {
    # P: one stroke loops like handwriting, runs out into a line, and a coral caret takes over.
    "P": tile(PAPER, f'<path d="M66 60 H38 A15 15 0 1 1 53 45" stroke="{INK}"/>'
                     f'<rect x="73" y="28" width="9" height="44" rx="4.5" fill="{CORAL}" stroke="none"/>'),
    # N: two open hooks holding each other: joined, but not a chain.
    "N": tile(PAPER, f'<path d="M62 28 H36 A16 16 0 0 0 36 60 H58" stroke="{INK}"/>'
                     f'<path d="M38 72 H64 A16 16 0 0 0 64 40 H42" stroke="{CORAL}"/>'),
    # O: a two-strand braid, ink over then coral over.
    "O": weave(PAPER, INK, CORAL, '<path d="M18 42 C32 42 34 58 50 58 S68 42 82 42"/>',
               '<path d="M18 58 C32 58 34 42 50 42 S68 58 82 58"/>', [(33.25, 50)], [(66.75, 50)]),
    "L": weave(PAPER, INK, CORAL, KA, KB, K_A_OVER, K_B_OVER),
    # M: L reversed onto ink, paper and coral strands.
    "M": weave(INK, PAPER, CORAL, KA, KB, K_A_OVER, K_B_OVER),
}

here = Path(__file__).parent
for name, svg in options.items():
    (here / f"{name}.svg").write_text(svg)
