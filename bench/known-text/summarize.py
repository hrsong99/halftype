"""Summary of known-text traces: summarize.py results/<model>.jsonl.gz ... -> a Markdown table and examples."""
import gzip
import json
import sys
from collections import defaultdict
from pathlib import Path

GROUPS = ["quotes", "idioms", "stock", "articles"]
runs = {Path(p).name.split(".jsonl")[0]: [json.loads(line) for line in gzip.open(p, "rt")] for p in sys.argv[1:]}

print("Positions: just after a space, and two letters into a word. Shown: passed the gate and the 3-key minimum.")
print("Right: first word exactly the next word. Saved: keys a Tab user doesn't press, Tab one key taking one word.\n")
print("| Model | Group | Positions | Shown | Right when shown | Right and shown, of positions | Saved |")
print("|---|---|---|---|---|---|---|")
for model, rows in runs.items():
    for group in GROUPS + ["all"]:
        pos = [r for r in rows if r["t"] == "pos" and r["kind"] != "other" and group in (r["group"], "all")]
        walk = [r for r in rows if r["t"] == "walk" and group in (r["group"], "all")]
        shown = [r for r in pos if r["shown"]]
        right = sum(r["right"] for r in shown)
        length = sum(r["len"] for r in walk)
        saved = (length - sum(r["keys"] for r in walk)) / length
        print(f"| {model} | {group} | {len(pos)} | {len(shown) / len(pos):.1%} | {right / max(len(shown), 1):.1%} "
              f"| {right / len(pos):.1%} | {saved:.1%} |")

# Examples: the same word-start positions across models, most disagreement first.
by_key = defaultdict(dict)
for model, rows in runs.items():
    for r in rows:
        if r["t"] == "pos" and r["kind"] == "start":
            by_key[(r["group"], r["item"], r["pos"])][model] = r
print("\n## Examples (prefix -> what each model shows; `-` nothing shown; * right)\n")
for group in GROUPS:
    keys = [k for k in by_key if k[0] == group and len(by_key[k]) == len(runs)]
    # Positions where some model is right and another isn't, earliest in the line first.
    split = [k for k in keys if len({by_key[k][m]["shown"] and by_key[k][m]["right"] for m in runs}) > 1]
    split.sort(key=lambda k: (k[2], k[1]))
    seen = set()
    split = [k for k in split if not (by_key[k][next(iter(runs))]["prefix"] in seen or seen.add(by_key[k][next(iter(runs))]["prefix"]))]
    print(f"**{group}**\n")
    for k in split[:6]:
        cells = [f"{m}: " + (f"`{by_key[k][m]['ghost']}`" + ("*" if by_key[k][m]["right"] else "") if by_key[k][m]["shown"] else "-")
                 for m in runs]
        print(f"- `{next(iter(by_key[k].values()))['prefix']}` -> " + "; ".join(cells))
    print()
