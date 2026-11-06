# Live test, by hand

What the automatic checks can't reach: the real Tab in real apps, and the Korean input method in Chromium. About 10 minutes, most important first.
`scripts/e2e.sh --ime` already proves Tab against Apple's live 2-set input method in a native text view: every jamo, and every composing state of 17 hard words.

**Before you start:** quit Cotypist, which also takes Tab. Quit and reopen T3 and ego lite, so the accessibility switches Cotypist
turned on are off, which is how anyone else's Mac starts. Run `scripts/build-app.sh`, then open `build/Itda.app`. Grant Accessibility at the
system's prompt. **Should happen:** within two seconds the menu's "Waiting for Accessibility" line goes, with no restart. The menu shows the
download, then the model's name (1.4 GB). You are never asked for Input Monitoring; if Tab does nothing below, tell me.

## 1. T3 composer, Korean 2-set: what matters most
The unknown: does Chromium's composition take real keys, F18 and then text the way a native field does?
1. Type `오늘 회의는 세 시에` and pause. **Should happen:** a ghost, its baseline in line with your Hangul.
2. **The syllable has to change.** Keep typing until the ghost continues past a syllable you've only half typed (`다음` from `다음`'s `다`, or any
   ghost whose word differs from what's on screen). Tab. **Should happen:** the syllable finishes itself and the word follows, in order. No stray
   `ㄴ`, no `ㅁ`, no box character (F18 leaving a character behind), and nothing lost.
3. **The syllable is already right.** A ghost that simply continues what you see. Tab. **Should happen:** the word follows. Then type on:
   the next syllable starts fresh, not joined to the last.
4. Press Tab twice fast with a ghost showing. **Should happen:** two words, each once.
5. Type a syllable, click at the end of the same line (or press an arrow and come back), and wait. **Should happen:** a ghost only if it fits what's
   there as it stands; Tab can't ever turn it into another syllable.
6. Type past the suggestion, then backspace. **Should happen:** nothing garbled, and a ghost only if it fits.
7. After a Tab, press Return to send. **Should happen:** no ghost on the emptied composer.

Any wrong character: tell me exactly what you typed and what came out. That's the one result I can't get without you.

## 2. ego lite, Korean
8. Repeat 1 to 4 in a plain text box (a search field), then in a rich editor (Gmail compose, or a chat box).
   **Should happen:** the same as T3. No ghost is the right failure; a misplaced ghost or a wrong character isn't.
9. Password field: type. **Should happen:** never a ghost.

## 3. Other Korean layouts, and F18
10. If you have 3-set: switch to it and type. **Should happen:** a ghost only where what's on screen needs no change, and Tab inserts it.
11. If anything of yours is bound to F18 (Karabiner, BetterTouchTool, a global hotkey), it fires on a Korean Tab. Tell me if so.

## 4. T3 composer, English
12. Type `Can you take a look at`, and pause. **Should happen:** grey text from the caret, on the baseline, same size as your text.
13. Tab: one word goes in, the rest stays lined up. Shift-Tab: all of it. Type the letters it shows: it shrinks and never lags the caret.
14. Scroll the conversation, click elsewhere, switch apps, move the window. **Should happen:** the ghost is gone at once each time.
15. With no ghost showing, press Tab. **Should happen:** T3 gets it as usual.

## 5. The rest
16. Menu: "Pause in <app>", then type there. **Should happen:** no ghost, Tab normal. Turn Itda off: no ghost anywhere. Quit: no crash report.
17. TextEdit and Messages, in dark mode too: repeat 1, 2 and 12. **Should happen:** readable grey.
18. Stop typing with Activity Monitor open (Memory tab, Memory Used and Wired at the bottom). **Should happen:** Wired falls 1.5 GB about 15 s after you stop;
    Itda's own Memory is about 250 MB, then falls about 5 minutes later. CPU around 0%.
