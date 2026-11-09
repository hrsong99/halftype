#!/usr/bin/env python3 -I
"""Public sentences for the typing comparison. Only their IDs are in the repo; the text is fetched at a pinned commit.

  text.py fetch <out dir>        download both sets, check their SHA-256, write <out>/en.tsv and <out>/ko.tsv (id, text)
  text.py select <tm1.json> <smile.tsv>   how ids.tsv was made: prints it

English: Taskmaster-1 self-dialogs (Google, CC BY 4.0), the USER side: people writing as a customer to an assistant.
Korean: SmileStyle (Smilegate AI, CC BY-NC 4.0), measuring only, with the same IDs and columns as docs/measuring.md's public set.
"""
import hashlib, json, os, random, sys, unicodedata, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCES = {
    "en": ("https://raw.githubusercontent.com/google-research-datasets/Taskmaster/d92cb6af3005f1dc09c39e75e7daf4a04905e00b/TM-1-2019/self-dialogs.json",
           "1e590ed0ccee279e40c2fb9e083d3b9417477c6bfe35ce5b2277167698dd858d"),
    "ko": ("https://raw.githubusercontent.com/smilegate-ai/korean_smile_style_dataset/b362299d1ac9a8a0de2f64eb8f55f3b386e97fad/smilestyle_dataset.tsv",
           "523ce83d6e9154e2357ca759460b487231aa0853bf98b208d0cb624a8e1e69bf"),
}
EN_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ,.?!'")
KO_SYMBOLS = set(" ,.?!0123456789")


def english(data):
    """{id: text} for every USER turn: tm1-<conversation>-<index>."""
    return {f"tm1-{d['conversation_id']}-{u['index']}": u["text"].strip()
            for d in data for u in d["utterances"] if u["speaker"] == "USER"}


def korean(lines):
    """{id: text}, as local-autocomplete/bench/build_corpus.py numbers them: smile-<dialogue>-<turn>, formal and informal by turns of dialogue."""
    dialogues, cur = [], []
    for i, line in enumerate(lines):
        cells = line.rstrip("\n").split("\t")
        if i == 0:
            continue
        if not any(c.strip() for c in cells):
            if cur:
                dialogues.append(cur)
            cur = []
        else:
            cur.append(cells)
    if cur:
        dialogues.append(cur)
    out = {}
    for d, turns in enumerate(dialogues):
        col = d % 2
        said = [unicodedata.normalize("NFC", t[col].strip()) for t in turns if len(t) > col]
        for i, text in enumerate(said):
            out[f"smile-{d}-{i}"] = text
    return out


def select(tm1, smile):
    words = {w.strip().lower() for w in open("/usr/share/dict/words")}
    rng = random.Random(20261109)
    en = english(json.load(open(tm1)))
    # Typable on ABC with no symbols the 2-set table lacks, 30-70 characters, and every word spelled as the system dictionary has it.
    ok = [k for k, t in sorted(en.items()) if 30 <= len(t) <= 70 and set(t) <= EN_CHARS
          and all(w.strip(",.?!'").lower() in words or "'" in w for w in t.split())]
    picked_en = rng.sample(ok, 24)
    ok_en = ok
    ko = korean(open(smile, encoding="utf-8"))
    # The test dialogues of measuring.md's split (every third), 14-40 characters, only whole syllables, spaces and plain punctuation.
    ok = [k for k, t in sorted(ko.items()) if int(k.split("-")[1]) % 3 == 0 and 14 <= len(t) <= 40
          and all(0xAC00 <= ord(c) <= 0xD7A3 or c in KO_SYMBOLS for c in t) and "  " not in t]
    picked_ko = rng.sample(ok, 16)
    # 41 more on 2026-11-10, so 64 are scored: 16 couldn't tell two apps 2 points apart. Drawn apart, so the first 24 and Korean stay.
    picked_en += random.Random(20261110).sample(sorted(set(ok_en) - set(picked_en)), 41)
    for k in picked_en:
        print(f"en\t{k}")
    for k in picked_ko:
        print(f"ko\t{k}")


def fetch(out):
    os.makedirs(out, exist_ok=True)
    ids = [l.rstrip("\n").split("\t") for l in open(os.path.join(HERE, "ids.tsv")) if l.strip() and not l.startswith("#")]
    for lang, (url, sha) in SOURCES.items():
        raw = urllib.request.urlopen(url, timeout=120).read()
        got = hashlib.sha256(raw).hexdigest()
        if got != sha:
            sys.exit(f"{lang}: {url} has SHA-256 {got}, expected {sha}")
        table = english(json.loads(raw)) if lang == "en" else korean(raw.decode("utf-8").splitlines(True))
        with open(os.path.join(out, f"{lang}.tsv"), "w", encoding="utf-8") as f:
            for l, k in ids:
                if l == lang:
                    f.write(f"{k}\t{table[k]}\n")
        print(f"{lang}: {sum(l == lang for l, _ in ids)} sentences to {out}/{lang}.tsv")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "fetch":
        fetch(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "select":
        select(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
