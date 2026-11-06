# Live test, by hand

What the automatic checks can't reach: the real Tab in real apps, and the Korean input method in Chromium. About 10 minutes, most important first.
`scripts/e2e.sh --ime` already proves Tab through a real tap against Apple's live 2-set input method in a native text view, both with the native marked range, empty over a live syllable, and saying nothing, plus a stated fake range for the branch that trusts one: every key, and every composing state of 17 hard words. `scripts/e2e.sh` proves the shipping tap's order on the session stream, with nothing reaching an app. Neither holds a real Shift key or reaches Chromium: steps 7 to 11 are why.

**Before you start:** quit Cotypist, which also takes Tab. Quit and reopen T3 and ego lite, so the accessibility switches Cotypist
turned on are off, which is how anyone else's Mac starts. Run `scripts/build-app.sh`, then open `build/Itda.app`. Grant Accessibility at the
system's prompt. **Should happen:** within two seconds the menu's "Waiting for Accessibility" line goes, with no restart. The menu shows the
download, then the model's name (1.4 GB). You are never asked for Input Monitoring; if Tab does nothing below, tell me.

## 1. T3 composer, Korean 2-set: what matters most
The unknown: does Chromium's composition take our key presses the way a native field does? Tab presses the keys of the next word, as if you typed them.
1. Type `오늘 회의는 세 시에` and pause. **Should happen:** a ghost, its baseline in line with your Hangul.
2. **The syllable has to change.** Keep typing until the ghost continues past a syllable you've only half typed (`다음` from `다`, or any
   ghost whose word differs from what's on screen). Tab. **Should happen:** the syllable finishes itself and the word follows, in order. No stray
   `ㄴ` or `ㅁ`, nothing lost. The last syllable is still composing, as if you'd typed it, so a next vowel may pull its final across: that's normal.
3. **The syllable is already right.** A ghost that simply continues what you see. Tab. **Should happen:** the word follows.
4. Press Tab twice fast with a ghost showing. **Should happen:** two words, each once.
5. Type a syllable, click at the end of the same line (or press an arrow and come back), and wait. **Should happen:** a ghost only if it fits what's
   there as it stands. Tab can never turn it into another syllable or leave `하ㄴ`.
6. Type past the suggestion, then backspace twice, then Tab on whatever ghost shows. **Should happen:** nothing garbled.
7. Backspace, then Tab as fast as your fingers go, ten times over. **Should happen:** Tab finishes the syllable or moves focus. Never a stray jamo.
8. Tab, then Backspace as fast as you can, then Tab on what shows. **Should happen:** the word comes out right: `다으` becomes `다음`, not `다으 날`.
9. Hold **left** Shift, press Tab on a ghost with `ㅆ` or `ㅃ` nearby and without, keep holding a moment. Again with **right** Shift. **Should happen:** the whole suggestion, the same characters both ways.
10. Caps Lock on, then Tab and Shift-Tab; Caps Lock off, the same. (Caps Lock on 2-set may switch you to ABC: then just say so.) **Should happen:** the same characters as with it off.
11. Tab at once after each of: clicking another field on the page, Cmd-Tab to another app and back. **Should happen:** Tab is that field's or app's. Never the ghost's text in the wrong place.
12. Type through a long ghost at full speed, letter for letter, and watch it. **Should happen:** it moves with you, no strobing. If it flashes: tell me, it's the one frame in `Watcher.oneFrame` that's too short for Chromium.
13. Tab, then at once Return. **Should happen:** the word is in the sent message, and no ghost on the emptied composer.
14. A ghost with Latin in its text: it stops before the first Latin letter, and Tab types only that part.

Any wrong character: tell me exactly what you typed and what came out. That's the one result I can't get without you.

## 2. ego lite, Korean
15. Repeat 1 to 4 and 8 in a plain text box (a search field), then in a rich editor (Gmail compose, or a chat box).
   **Should happen:** the same as T3. No ghost is the right failure; a misplaced ghost or a wrong character isn't.
16. Password field: type. **Should happen:** never a ghost.

## 3. Other Korean layouts
17. If you have 3-set: switch to it and type. **Should happen:** no ghost while the last character is Hangul; after a space a ghost may show, and Tab inserts it.

## 4. T3 composer, English
18. Type `Can you take a look at`, and pause. **Should happen:** grey text from the caret, on the baseline, same size as your text.
19. Tab: one word goes in, the rest stays lined up. Shift-Tab: all of it. Type the letters it shows: it shrinks and never lags the caret.
20. Scroll the conversation, click elsewhere, switch apps, move the window, press Esc. **Should happen:** the ghost is gone at once each time, and Tab is the app's.
21. With no ghost showing, press Tab. **Should happen:** T3 gets it as usual.

## 5. The rest
22. Menu: "Pause in <app>", then type there. **Should happen:** no ghost, Tab normal. Turn Itda off: no ghost anywhere. Quit: no crash report.
23. TextEdit, in dark mode: repeat 1, 2 and 18. **Should happen:** readable grey.

Memory and CPU have their own numbers in `docs/measuring.md`, and take five idle minutes, so they aren't here.
