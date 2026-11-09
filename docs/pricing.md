# Pricing and licence (decided 2026-11-09)

## Now
- The app stays free, under MIT. Published source is how users check the privacy promise, and the MIT commits can't be taken back anyway.
- **Early-bird list (live 2026-11-09):** a Google Form, [viewform](https://docs.google.com/forms/d/e/1FAIpQLSeIekyjCphdrP9pZ9zaj5P90plPghgLAJ3zYof6PEji1uo9UQ/viewform), owned by hrsong99@gmail.com ("Halftype early birds (waitlist)" in Drive; read with `gws forms forms responses list`). Linked from the README; not from the app, so the network promise holds. Move the emails to Kit (free to 10,000) once there's something to send: sending needs a postal address in each email.
- **Donations:** GitHub Sponsors, live 2026-11-09 at https://github.com/sponsors/hrsong99 (South Korea, no fee on personal sponsorships). Stripe pays out in KRW to John's 토스뱅크 통장. The repo's Sponsor button is `.github/FUNDING.yml`. Tiers (2026-11-09, a guess): $3/month and $10 one-time, no rewards, plus a custom amount.
- **Usage numbers, with no analytics in the app:** `scripts/usage.sh`, from GitHub's download counts. New installs = `Halftype.dmg`, updates = `Halftype-update.dmg` (the appcast's file, from the release after 0.1.8 on), roughly running installs = appcast fetches per day.

## Pro, later: only if the fake door shows demand
- **What it is:** Personal Model, a LoRA trained on the user's own text (sent Mail, Messages, a KakaoTalk export, then what they type) and retrained as it grows.
- **Trained on a rented GPU, not the Mac (changed 2026-11-09):** on-device training depends on a laptop we can't see, and when it's idle; a bad experience. The Mac sends the training rows over TLS to a serverless GPU (Modal), which keeps them only in the job's `/tmp`, deletes them before it returns, logs counts only, and sends back the adapter, which stays on the Mac. It works for John's own adapter now: `lab/cloud/` on `learn`. **Cost per run, measured 2026-11-09:** John's 3,014 messages (493k tokens), Kanana on an L4, trained in 448 s, ~10 min billed with start-up and model load: ~$0.15 at $0.80/h, inside Modal's $30/month free credit. Validation loss 2.63, against the Mac's 2.61. Before anyone else's text goes up: Modal's retention of call inputs and outputs, a data processing agreement, a privacy policy (PIPA, GDPR), and the README's "nothing you type is sent" changed in the same release. Confidential GPUs (attested, as Apple's Private Cloud Compute) are the stronger promise, at ~5-9× the price; Colab and Kaggle are not for customer text.
- **Price (a guess, not tested):** $4/month, $36–40/year, $99 lifetime. Lifetime is set at ~2.5× the yearly price, as Superwhisper does (~2.9×). At 2× (for example $80), most buyers would take lifetime and the recurring revenue would never come.
- **Store: a merchant of record, not GitHub Sponsors (decided 2026-11-09).** Sponsors takes no fee, but buyers need a GitHub account (most Halftype users aren't developers), it has no yearly plan, a licence key makes a sponsorship a sale whose Korean 부가세 and EU VAT would be John's to file, and GitHub's terms don't say licence-key rewards are allowed. Check Polar first (built for open source, licence keys, yearly plans, ~4% + 40¢; Korea payouts unconfirmed), else Lemon Squeezy (5% + 50¢, pays out to Korea). Selling Pro is a business: register (홈택스, free) before launch. Sponsors stay donations.
- **The licence check works offline** (a signed key checked locally). Training is new network use, so it's opt-in and named in the README.
- **Retraining cadence:** when someone's history has grown by about half, not every week. The gain was ~+1.1 points per tripling of history (`lab/PLAYBOOK.md` on `learn`), so weekly retrains add almost nothing.
- **Fake door first:** a "Personal Model: $4/mo" row in the window, that opens the early-bird form in the browser: the app can't count clicks without new network use, so form sign-ups against running installs (`scripts/usage.sh`) are the measure, before building the trainer or billing.

## Early birds
- Anyone who installs before Pro launches gets Personal Model free for good, retraining included: each retrain costs ~$0.15 (above), so the promise is affordable. It doesn't cover other future cloud features.
- Who counts: the first day in the install's Stats (`Tally.since`, never pruned) is before launch day. Resetting Stats loses it; a separate first-launch date would fix that if it matters.

## Copy: say only what's true
- True: "Your model keeps learning. Halftype retrains it as your writing grows, and new base models come with updates."
- True now that training runs on rented GPUs: the subscription pays for retraining runs as well as the work (new models, the app). Keep it to "retraining runs on our GPUs": the cost per user is cents, so don't imply it's large.
- Retraining as they type means saving typed text on the Mac. That changes the README's "never saved" line, in the same commit as the feature.
