# Model view (round 1, 2026-11-09)

Question: how John could see what the model sees when it suggests. John: "I'm kind of curious what kind of context is in the model when it's suggesting… a toggle where I can see the information hovering over the suggestion, or a keyboard shortcut that I can press to see what it's seeing and why it's predicting its next tokens."

What the model sees today: the screen text before the field (Accessibility, up to 1200 chars), a blank line, then the field's text up to the last whole word. The half-typed word and a composing syllable are held back and forced at the logits. No instructions. Greedy decoding, so "why" means each token's probability, the e^-1 running floor that ends the ghost, and the Gate (first word ≥ e^-0.7).

- `index.html`: options A–F built as HTML, on one invented chat moment (`Sounds good, see you tomo` → `rrow at the`, with stop and Gate numbers that follow the shipped rules), plus image ideas G–I.
- `options.png`: a frozen screenshot of A–F (dark).
- `images/`: Codex image ideas `g-popover`, `h-xray`, `i-docked` (.png originals, .jpg for the page), with `*.prompt.txt` and `gen.sh`. `today.jpg` (a live TextEdit ghost from accept-motion) was passed as a reference.

Recommendation: B, an inspector panel opened from the menu bar. It needs no engine change and can't cover your typing. C, hold ⌃⌥ to peek at the caret, if you'd rather have it where you look.

## Pick

John picked C, polished as G: "C (or polished version G) is kind of what i was imagining… as a debug feature that users can turn on". Built as General › Show What the Model Sees (off by default): hold ⌃⌥ over a ghost (`Sources/HalftypeApp/Peek.swift`, numbers from `Peek.make` in `Generation.swift`). The modifiers are watched by NSEvent monitors, never taken. No runner-up words yet: they need the engine to keep more than the picked token. `built/17-peek-*.png` come from `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots/peek`.
