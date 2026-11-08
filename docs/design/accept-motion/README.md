# Accept motion (2026-11-09)

Question: what plays when Tab takes words in other apps. John: "I don't see [the glint]… I want to see the realistic animations we could have for when we accept a suggestion in most apps."

Why he didn't see it: `GhostPanel.took` plays the glint only when `layout.glass`, which is true only in our own window (Try It). In Slack, Mail, Notes and every other app, Tab has no motion.

- `index.html`: round 1, options A–G on one clock, with replay, slow-motion and dark-mode controls. Each is something our click-through panel can paint over the host's text where the ghost was drawn. We can't recolour the host's own text.

Recommendation: D, the underline sweep. It draws no letters, so a font or zoom mismatch with the host can't show doubled text. C, ink settle, is the alternative if D feels like too much.

Pick: (pending)

## Round 2

John: "not every app has perfectly aligned text and suggestions (most don't I guess), so a lot of these won't look good right? Can you show me variations that can still look good? Maybe those that deal with the caret?"

- `round2.html`: six options (A spark, B glow, C caret flash, D trail, E ripple, F halftone puff), each drawn only from the caret position the app reports, never from letters or word boxes. Recommendation: C, the caret flash.
