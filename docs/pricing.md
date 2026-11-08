# Pricing and licence (decided 2026-11-09, nothing built yet)

## Now
- The app stays free, under MIT. Published source is how users check the privacy promise, and the MIT commits can't be taken back anyway.
- Add a donation link (GitHub Sponsors or pay-what-you-want) and an optional early-bird email list (a web form, not in the app, so the README's network promise holds).

## Pro, later: only if the fake door shows demand
- **What it is:** Personal Model, a LoRA trained **on the user's Mac**, starting from text they already have (sent Mail, Messages, a KakaoTalk export) and retrained as their typing grows. On-device training costs us $0 per user and keeps the text on the Mac. Server training was ruled out: its cost recurs, it means uploading everything people type, and it brings privacy-law work (PIPA, GDPR).
- **Price (a guess, not tested):** $4/month, $36–40/year, $99 lifetime. Lifetime is set at ~2.5× the yearly price, as Superwhisper does (~2.9×). At 2× (for example $80), most buyers would take lifetime and the recurring revenue would never come.
- **The licence check works offline** (a signed key checked locally), so no new network use.
- **Retraining cadence:** when someone's history has grown by about half, not every week. The gain was ~+1.1 points per tripling of history (`lab/PLAYBOOK.md` on `learn`), so weekly retrains add almost nothing.
- **Fake door first:** a "Personal Model: $4/mo" row in the window, with clicks counted against active users, before building the trainer or billing.

## Early birds
- Anyone who installs before Pro launches gets Personal Model free for good. The promise covers features that run on their Mac, never future cloud ones.
- Who counts: the first day in the install's Stats (`Tally.since`, never pruned) is before launch day. Resetting Stats loses it; a separate first-launch date would fix that if it matters.

## Copy: say only what's true
- True: "Your model keeps learning. Halftype retrains it on your Mac as your writing grows, and new base models come with updates."
- Not true while training stays on-device: "running costs on our side". The subscription pays for continued work (retraining, new models, the app), not for servers.
- Retraining as they type means saving typed text on the Mac. That changes the README's "never saved" line, in the same commit as the feature.
