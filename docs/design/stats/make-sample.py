# Writes sample-tally.json: 2026-11-08 is the real count from this Mac's stats.json (counts only);
# the 13 days before are made up (the store only has one day), shaped like it. Odd dates = personal model on (Compare).
import json
tabs = [118, 142, 96, 163, 131, 24, 0, 151, 176, 120, 204, 158, 47]
days = {}
for i, t in enumerate(tabs):
    d = 26 + i
    key = f"2026-10-{d:02d}" if d <= 31 else f"2026-11-{d-31:02d}"
    day = int(key[-2:])
    chars = round(t * 4.1)
    rate = 0.124 if day % 2 else 0.108
    saved = round(chars * 0.62)
    typed = round(saved * (1 - rate) / rate) if t else 0
    days[key] = dict(shown=round(t * 12.3), taken=round(t * 0.54), tabs=t, characters=chars,
                     typed=typed, saved=saved, withModel=bool(day % 2), withoutModel=not day % 2)
days["2026-11-08"] = {"typed":3848,"withoutModel":True,"tabs":189,"withModel":False,"taken":102,"saved":481,"characters":770,"shown":2328}
json.dump({"days": days}, open("sample-tally.json", "w"), indent=1)
