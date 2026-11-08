"""Fetches shipping app icons from Apple's iTunes Search API for the reference page. Run: python3 fetch.py
The icons are other companies' trademarks: they stay local (gitignored), only this script and the page are committed."""
import json, urllib.parse, urllib.request
from pathlib import Path

# (file name, search term, expected seller substring)
APPS = [
    ("grammarly", "Grammarly AI Keyboard", "superhuman platform"),
    ("textexpander", "TextExpander", "textexpander"), ("iawriter", "iA Writer", "information architects"),
    ("ulysses", "Ulysses writing app", "ulysses"), ("bear", "Bear markdown notes", "shiny frog"),
    ("drafts", "Drafts", "agile tortoise"), ("superwhisper", "superwhisper", "superultra"),
    ("wispr", "Wispr Flow", "wispr"), ("raycast", "Raycast", "raycast"),
    ("chatgpt", "ChatGPT", "openai"), ("claude", "Claude by Anthropic", "anthropic"),
    ("perplexity", "Perplexity AI", "perplexity"), ("granola", "Granola AI notepad", "granola"),
    ("notion", "Notion", "notion"), ("linear", "Linear", "linear orbit"),
    ("things", "Things 3", "cultured code"), ("superhuman", "Superhuman email", "superhuman"),
    ("craft", "Craft docs", "craft"), ("fantastical", "Fantastical", "flexibits"),
    ("arc", "Arc Search", "browser company"),
]
# Not in the App Store: the icon their own site serves.
WEB = [("cotypist", "Cotypist", "https://cotypist.app/apple-touch-icon.png"),
       ("cursor", "Cursor", "https://cursor.com/marketing-static/icon-192x192-light.png"),
       ("mimestream", "Mimestream", "https://mimestream.com/assets/icons/apple-touch-icon.png"),
       ("cleanshot", "CleanShot X", "https://cleanshot.com/favicon@2x.png")]
here = Path(__file__).parent
found = {}
for name, app, url in WEB:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    (here / f"{name}.png").write_bytes(urllib.request.urlopen(req, timeout=20).read())
    found[name] = {"app": app, "platform": "web", "url": url}
    print(name, "web")
for name, term, seller in APPS:
    for entity in ("macSoftware", "software"):
        q = urllib.parse.urlencode({"term": term, "entity": entity, "limit": 8, "country": "us"})
        res = json.load(urllib.request.urlopen(f"https://itunes.apple.com/search?{q}", timeout=20))["results"]
        hit = next((r for r in res if seller in (r.get("sellerName", "") + r.get("artistName", "")).lower()), None)
        if hit:
            url = hit["artworkUrl512"]
            (here / f"{name}.png").write_bytes(urllib.request.urlopen(url, timeout=20).read())
            found[name] = {"app": hit["trackName"], "platform": "mac" if entity == "macSoftware" else "ios", "url": hit["trackViewUrl"]}
            break
    print(name, found.get(name, "NOT FOUND"))
(here / "found.json").write_text(json.dumps(found, indent=1, ensure_ascii=False))
