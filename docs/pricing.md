# Pricing and licence (decided 2026-11-09)

## Now
- The app stays free, under MIT. Published source is how users check the privacy promise, and the MIT commits can't be taken back anyway.
- **Early-bird list (live 2026-11-09):** a Google Form, [viewform](https://docs.google.com/forms/d/e/1FAIpQLSeIekyjCphdrP9pZ9zaj5P90plPghgLAJ3zYof6PEji1uo9UQ/viewform), owned by hrsong99@gmail.com ("Halftype early birds (waitlist)" in Drive; read with `gws forms forms responses list`). Linked from the README; not from the app, so the network promise holds. Move the emails to Kit (free to 10,000) once there's something to send: sending needs a postal address in each email.
- **Donations:** GitHub Sponsors (South Korea is a supported region, no fee on personal sponsorships). John enrols himself (bank and tax form), then add `.github/FUNDING.yml` with `github: hrsong99`.
- **Usage numbers, with no analytics in the app:** `scripts/usage.sh`, from GitHub's download counts. New installs = `Halftype.dmg`, updates = `Halftype-update.dmg` (the appcast's file, from the release after 0.1.8 on), roughly running installs = appcast fetches per day.

## Pro, later: only if the fake door shows demand
- **What it is:** Personal Model, a LoRA trained **on the user's Mac**, starting from text they already have (sent Mail, Messages, a KakaoTalk export) and retrained as their typing grows. On-device training costs us $0 per user and keeps the text on the Mac. Server training was ruled out: its cost recurs, it means uploading everything people type, and it brings privacy-law work (PIPA, GDPR).
- **Price (a guess, not tested):** $4/month, $36–40/year, $99 lifetime. Lifetime is set at ~2.5× the yearly price, as Superwhisper does (~2.9×). At 2× (for example $80), most buyers would take lifetime and the recurring revenue would never come.
- **Store:** Lemon Squeezy (merchant of record, built-in licence keys, bank payouts to Korea, 5% + 50¢). Check Polar and Paddle for Korea again when it's time.
- **The licence check works offline** (a signed key checked locally), so no new network use.
- **Retraining cadence:** when someone's history has grown by about half, not every week. The gain was ~+1.1 points per tripling of history (`lab/PLAYBOOK.md` on `learn`), so weekly retrains add almost nothing.
- **Fake door first:** a "Personal Model: $4/mo" row in the window, that opens the early-bird form in the browser: the app can't count clicks without new network use, so form sign-ups against running installs (`scripts/usage.sh`) are the measure, before building the trainer or billing.

## Early birds
- Anyone who installs before Pro launches gets Personal Model free for good. The promise covers features that run on their Mac, never future cloud ones.
- Who counts: the first day in the install's Stats (`Tally.since`, never pruned) is before launch day. Resetting Stats loses it; a separate first-launch date would fix that if it matters.

## Copy: say only what's true
- True: "Your model keeps learning. Halftype retrains it on your Mac as your writing grows, and new base models come with updates."
- Not true while training stays on-device: "running costs on our side". The subscription pays for continued work (retraining, new models, the app), not for servers.
- Retraining as they type means saving typed text on the Mac. That changes the README's "never saved" line, in the same commit as the feature.
