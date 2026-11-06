# Live test, by hand

What the automatic checks can't reach: the real Tab in real apps, and the Korean input method in Chromium. About 10 minutes.
`scripts/e2e.sh` has already covered the private-window loop.

**Before you start:** quit Cotypist, which also takes Tab. Quit and reopen T3 and ego lite, so the accessibility switches Cotypist
turned on are off, which is how anyone else's Mac starts. Run `scripts/build-app.sh`, then open `build/Itda.app`.

## Permissions
1. First launch shows the system's Accessibility prompt, once. Open Settings from it and turn Itda on.
   **Should happen:** within a second or two the menu's "Waiting for Accessibility" line goes, with no restart.
2. Look at Settings > Privacy & Security > Input Monitoring.
   **Should happen:** Itda isn't listed, and you were never asked. If it is, or Tab does nothing in the steps below, tell me.
3. Rebuild with `scripts/build-app.sh` and reopen. **Should happen:** no new prompt, and Itda keeps working.
4. Menu bar icon: **Should show** download progress, then the model's name. Wait for it (1.4 GB).

## T3 composer, English
5. Type `Can you take a look at`, and pause. **Should happen:** grey text from the caret, on the baseline, same size as your text.
6. Tab. **Should happen:** one word goes in, the ghost keeps the rest and stays lined up. Shift-Tab: all of it goes in.
7. Keep typing the letters the ghost shows. **Should happen:** it shrinks letter by letter and never lags behind the caret.
8. Scroll the conversation, click elsewhere, switch apps, move the window. **Should happen:** the ghost is gone at once each time.
9. Type a long line until the ghost reaches the right edge. **Should happen:** it stops at a word, nothing past the composer's edge.
10. With no ghost showing, press Tab. **Should happen:** T3 gets it as usual.
11. Send a message, then type in the emptied composer. **Should happen:** suggestions now know about what was just said.

## T3 composer, Korean 2-set: the one that matters most
12. Type `오늘 회의는 세 시에` and pause. **Should happen:** a ghost, baseline in line with your Hangul.
13. Type until a syllable is still composing (`시작하` with `하` still open) and wait for a ghost starting after it. Press Tab.
    **Should happen:** `하` commits first and the word follows it, in order. No lost syllable, no text before it, no stray `ㅁ`.
    This worked in a native text view. **Chromium is the unknown:** tell me exactly what came out if not.
14. Press Tab twice fast with a ghost showing. **Should happen:** two words, each once.
15. When the next key would change the syllable you're composing (typed `하`, suggestion needs `한`). **Should happen:** no ghost until
    you type `ㄴ`, then the ghost picks up after `한`. No flicker of wrong text.
16. Type on past the suggestion, then use backspace to go back. **Should happen:** nothing garbled, ghost returns only if it fits.

## ego lite
17. Repeat 5, 6, 12 and 13 in a plain text box (a search field) and in a rich editor (Gmail compose, or a chat box).
    **Should happen:** the same as T3. Note any box where no ghost appears: no ghost is the right failure, a misplaced one isn't.
18. Password field: type. **Should happen:** never a ghost.

## Elsewhere
19. In a full-screen window and on your second display: repeat 5. **Should happen:** the ghost is at the caret on that display.
20. TextEdit, Notes, Messages: repeat 5, 6 and 13. In dark mode too. **Should happen:** readable grey in both.
21. Menu: "Pause in <app>", then type there. **Should happen:** no ghost, Tab normal. Turn Itda off: no ghost anywhere.
22. Activity Monitor with Itda idle: **should be** around 0% CPU, and memory falls back about 5 minutes after you last typed.
