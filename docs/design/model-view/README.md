# Model view (round 1, 2026-11-09)

Question: how John could see what the model sees when it suggests. John: "I'm kind of curious what kind of context is in the model when it's suggesting… a toggle where I can see the information hovering over the suggestion, or a keyboard shortcut that I can press to see what it's seeing and why it's predicting its next tokens."

What the model sees today: the screen text before the field (Accessibility, up to 1200 chars), a blank line, then the field's text up to the last whole word. The half-typed word and a composing syllable are held back and forced at the logits. No instructions. Greedy decoding, so "why" means each token's probability, the e^-1 running floor that ends the ghost, and the Gate (first word ≥ e^-0.7).

- `index.html`: options A–F built as HTML, on one invented chat moment (`Sounds good, see you tomo` → `rrow at the`, with stop and Gate numbers that follow the shipped rules), plus image ideas G–I.
- `options.png`: a frozen screenshot of A–F (dark).
- `images/`: Codex image ideas `g-popover`, `h-xray`, `i-docked` (.png originals, .jpg for the page), with `*.prompt.txt` and `gen.sh`. `today.jpg` (a live TextEdit ghost from accept-motion) was passed as a reference.

Recommendation: B, an inspector panel opened from the menu bar. It needs no engine change and can't cover your typing. C, hold ⌃⌥ to peek at the caret, if you'd rather have it where you look.

## Pick

John picked C, polished as G: "C (or polished version G) is kind of what i was imagining… as a debug feature that users can turn on". Built as General › Show What the Model Sees (off by default): hold ⌃⌥ over a ghost (`Sources/HalftypeApp/Peek.swift`, numbers from `Peek.make` in `Generation.swift`). The modifiers are watched by NSEvent monitors, never taken. No runner-up words yet: they need the engine to keep more than the picked token. `built/17-peek-*.png` come from `HALFTYPE_SHOTS=<dir> swift test --disable-keychain --filter WindowShots/peek`.

Live check, 2026-11-09 (TextEdit, Gemma 4 E2B, ⌃⌥ posted at the HID level): `built/live-1-tomorrow.png` (before the fix: a word followed from an older request read "omorrow", the part after its held "t"; the first word now shows whole), `built/live-2-appreciate.png`, `built/live-3-released.png` (card gone on release, ghost kept).
Round 2 (John: "the context part looks confusing, surely not the entire thing?"): two labelled sections, From the Screen and In the Field, split where `Prompt.screenChars` says, not at a guessed blank line; the last lines nearest the caret; ⇧ with ⌃⌥ shows the whole prompt. `built/18-peek-{light,dark,whole-dark}.png`.
Round 3 (John: "I want to see when I press, more like a toggle, above my cursor when suggestions show up"): a tap of ⌃⌥ turns the card on over every ghost until the next tap; ⌃⌥⇧ for the whole prompt (holding ⇧ to expand would fire on every capital). `PeekTap` decides on letting go of ⌃ or ⌥, which must be down together with no key between.
Live check of the toggle, 2026-11-09 (TextEdit, Gemma 4 E2B): `built/live-4-toggle.mp4` (tap, type, tap again) and `built/live-4-toggle-card.png`. The card follows each ghost and stops after the second tap; it goes away between ghosts, and below the line when the line sits under ~330 pt from the top of the screen. The first launch of that build showed no ghost at all, with or without the card; two relaunches were fine, cause unknown.
Round 4 (John: "even when I finished the word it still shows its percentage as if incomplete, and accepted words don't update"): the model is asked once per suggestion and the ghost is followed as you type or Tab, so the card describes that one request. It now ticks off words already typed or accepted (`Peek.taken`, set by the watcher from the ghost left), and the field label says "when suggested". Numbers stay as they were, so the cut word still matches the stop reason. `built/19-peek-*.png`.
Live check of the ticks, 2026-11-09: `built/live-5-taken.png` (two Tabs, "have" and "access" ticked). The first launch after a fresh build again showed no ghost (Tab typed tabs); a relaunch of the same build worked. Seen twice now; cause unknown.
The first-launch miss: John updated to 0.1.12 through Sparkle and suggestions worked, so it is taken as a quirk of starting a fresh build from the shell; AGENTS.md says to relaunch once.
