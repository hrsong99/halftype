# halftype.app

- `a2/`: the live page at https://halftype.app. Hand-built on the app's tokens (cream, the icon's blurred arch, glass suggestions with the Tab glint); it won the landing-polish round at 8.5 (`docs/design/landing-polish/`: playbook, reviews, `builds/H` with its notes and screenshots). Change a claim or number here and in the README together.
- `deploy.sh`: publishes `a2/` and `nginx.conf` to js, where the Dokploy compose `halftype-site` (composeId `IftjGPskKJyG74nM4i5Vv`, Side Projects) serves them with nginx; `www` redirects to the apex. DNS: A `@` and `www` → 152.69.228.186 at Spaceship.
- `compare/`: the measurements against other apps behind the page's comparison, their method and `idle.sh`.
- The page's suggestion gradient uses darker stops (`#45709d → #606e7e → #995e3e`) than the app's, for 4.5:1 contrast.
- Earlier drafts (A, B, the kit-built A2, rounds 1-4) are in git before 2026-11-09's switch; `git log -- docs/site/a` finds them. Some still sit on the share link in `share-link.txt` (remove with `ssh js rm -r share-site/html/o01ct9f75y5orO6q`).
- Domains, 2026-11-09: halftype.app $8.28 the first year, then $14.49 a year (bought).
