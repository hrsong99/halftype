# Accept motion (2026-11-09)

Question: what plays when Tab takes words in other apps. John: "I don't see [the glint]… I want to see the realistic animations we could have for when we accept a suggestion in most apps."

Why he didn't see it: `GhostPanel.took` plays the glint only when `layout.glass`, which is true only in our own window (Try It). In Slack, Mail, Notes and every other app, Tab has no motion.

- `index.html`: round 1, options A–G on one clock, with replay, slow-motion and dark-mode controls. Each is something our click-through panel can paint over the host's text where the ghost was drawn. We can't recolour the host's own text.

Recommendation: D, the underline sweep. It draws no letters, so a font or zoom mismatch with the host can't show doubled text. C, ink settle, is the alternative if D feels like too much.

Pick (after round 2): John chose round 2's C and D, with D, the trail, as the default, picked in General > Taking Words with a live preview. Try It keeps its glint. Built in `AcceptMotion` (GhostPanel.swift); `built/` has the General page.

## Round 2

John: "not every app has perfectly aligned text and suggestions (most don't I guess), so a lot of these won't look good right? Can you show me variations that can still look good? Maybe those that deal with the caret?"

- `round2.html`: six options (A spark, B glow, C caret flash, D trail, E ripple, F halftone puff), each drawn only from the caret position the app reports, never from letters or word boxes. Recommendation: C, the caret flash.

## Live check (2026-11-09, TextEdit, dark mode, built app d94e500..ddc11ff)

Recorded at 60 fps with `screencapture -v` while `scripts/live-keys.swift` typed "Please let me know if you ha" and pressed Tab three times. Frames in `live/`:
- `trail-textedit.jpg`: the line under "access" shrinks into the caret in about 6 frames (100 ms), drawn under the letters, never over them.
- `flash-textedit.jpg`: the caret itself goes blue to peach for about 12 frames (200 ms), exactly on TextEdit's caret. It starts about 4 frames (~70 ms) after the words appear, the time until TextEdit reports its new caret.
- `wrap-falls-back-to-flash.jpg`: with the window narrowed so "access" lands on the next line, Trail plays the flash there instead.

Not yet checked live: a Chromium host (Slack, Chrome), and a Korean 2-set Tab.
