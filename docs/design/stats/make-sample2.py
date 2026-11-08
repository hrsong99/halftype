# Round 2 sample: 16 weeks, Jul 20 – Nov 9 2026, made up (weekday rhythm, slow growth, noise; odd dates with the
# personal model, as Compare does). Nov 8 and 9 are this Mac's real counts (counts only).
import json, random, datetime
random.seed(7)
start, end = datetime.date(2026, 7, 20), datetime.date(2026, 11, 9)
days, d = {}, start
while d <= end:
    i = (d - start).days
    base = [150, 165, 140, 170, 130, 35, 10][d.weekday()] * (0.45 + 0.55 * i / 112)
    t = max(0, round(base * random.uniform(0.6, 1.3))) if random.random() > 0.08 else 0
    model = d.day % 2 == 1
    rate = (0.13 if model else 0.11) * random.uniform(0.85, 1.15)
    chars = round(t * 4.2); saved = round(chars * 0.7); typed = round(saved * (1 - rate) / rate) if t else 0
    days[d.isoformat()] = dict(shown=round(t * 11.5), taken=round(t * 0.52), tabs=t, characters=chars, typed=typed, saved=saved, withModel=model, withoutModel=not model)
    d += datetime.timedelta(days=1)
real = json.load(open("real-2days.json"))["days"]
days.update(real)
json.dump({"days": days}, open("sample-tally-2.json", "w"), indent=1)
