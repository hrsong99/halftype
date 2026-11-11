#!/usr/bin/env python3
"""Whole-machine power per app, from `powermetrics -f plist` samples (README "Power").

  python3 -I bench/compare/power.py <powermetrics.plist> <run dir>             each app's typing, from resources.jsonl
  python3 -I bench/compare/power.py <powermetrics.plist> <label> <start> <end>  any window, in Unix seconds (idle.sh)

Prints mean CPU, GPU and combined power in mW over the window. One app runs at a time, so the machine's power is that app's
plus a shared floor: the harness's own screen reads while typing, the idle Mac at rest.
"""
import calendar, json, plistlib, sys


def samples(path):
    out = []
    for chunk in open(path, 'rb').read().split(b'\0'):
        if chunk.strip():
            p = plistlib.loads(chunk.strip())
            t = calendar.timegm(p['timestamp'].timetuple())  # powermetrics stamps in UTC
            out.append((t, p['processor']))
    return out


def mean(s, start, end):
    w = [p for t, p in s if start <= t <= end]
    if not w:
        return None
    return len(w), {k: sum(p.get(k, 0) for p in w) / len(w) for k in ('cpu_power', 'gpu_power', 'combined_power')}


def show(label, r):
    if r is None:
        print(f'{label}: no samples in its window')
    else:
        n, m = r
        print(f"{label}: cpu {m['cpu_power']:.0f} mW, gpu {m['gpu_power']:.0f} mW, combined {m['combined_power']:.0f} mW ({n} s)")


if __name__ == '__main__':
    s = samples(sys.argv[1])
    if len(sys.argv) == 5:
        show(sys.argv[2], mean(s, float(sys.argv[3]), float(sys.argv[4])))
    else:
        for line in open(sys.argv[2] + '/resources.jsonl'):
            r = json.loads(line)
            if r.get('start') is None:
                print(f"{r['app']} {r['lang']}: no start time (a run before 2026-11-12)")
                continue
            show(f"{r['app']} {r['lang']}", mean(s, r['start'], r['start'] + r['seconds']))
    # self-check: a window holding no sample says so rather than printing zeros
    assert mean([(10, {'cpu_power': 1})], 20, 30) is None
