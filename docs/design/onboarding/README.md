# Onboarding (round 1)

John, 2026-11-09: "i want a delightful onboarding experience like from arc or dia… and a really seamless one (like for accessibility, I see a lot of apps have an overlay where you can drag the app into accessibility and stuff, do we need that?)… our default is Gemma 4, and we can start downloading the moment the app opens."

- `index.html`: A (today) and B–F, animated on one clock (Replay, 0.5×, scrub; `#t=6` freezes at 6 s). G–I are Codex images.
- `options.png`: the page frozen at 10.2 s.
- `today/`: what shipped on 2026-11-09, from `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots`.
- `images/`: G–I, their prompts in `prompts/`, remade one at a time with `images/gen.sh G` (refs: `icon.png`, `today.png`).

Recommended: C's four steps, with D's docked Settings guide as step 2 and E's practice field as step 3. 
## Pick (2026-11-09)

John: "Your pick sounds good, but I think H looks better than D" and "the onboarding of tab/tab shift, it should use the glass/glimmer animation of 'try it' in the app".
Built on branch `onboarding`: C's four steps (`Sources/HalftypeApp/Onboarding.swift`); H's card docked beside System Settings, with D's behaviour (drag-in fallback, gone on the grant, Halftype back in front) (`SettingsGuide` in `Practice.swift`); and step 3 is the real Try It field, so Tab draws the real glass and glint, answered by `Practice` until the model is in. `built/` holds the window shots (`17-onboarding-*`).
