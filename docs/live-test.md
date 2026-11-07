# Live test, by hand

What the automatic checks can't reach: the real Tab in real apps, and Korean in Chromium. Most important first; each step is what to do, then **what should happen**. Stop when your 10 minutes are up: what's left matters least.
Any wrong character: tell me what you typed and what came out. Use a new, empty T3 thread, as step 11 sends a message.

## Before you start (the first time, wait for a 0.5 GB download; it isn't part of the 10 minutes)
A. Quit Cotypist, which also takes Tab, then quit and reopen T3 and ego lite, so the accessibility switches it turned on are off.
   **Cotypist's icon is gone from the menu bar, and both apps are back.**
B. Open `build/Itda.app`; its window asks for Accessibility. Press the button and grant it.
   **Within 2 s the window shows its field, with no restart, and the download below it until the model is ready. Never a prompt for Input Monitoring.**

## T3 composer, Korean 2-set: about 5 minutes
This is the unknown: does Chromium's composition take our key presses the way a native field does?
1. Type `오늘 회의는 세 시에` and pause.
   **A ghost, its baseline in line with your Hangul.**
2. Keep typing until a ghost continues past a half-typed syllable (`다음` from `다`), then Tab.
   **The syllable finishes and the word follows, in order, no stray `ㄴ` or `ㅁ`. A next vowel may pull the last final across: that's normal.**
3. On a ghost of two or more words, press Tab twice fast. Then on a one-word ghost, press Tab twice fast.
   **Two words, each once. On the one-word ghost, say what the second Tab did: it goes to T3 if no new ghost is up yet.**
4. Type a syllable, press Left then Right, wait, and Tab on whatever ghost shows.
   **A ghost only if it fits what's there; never `하ㄴ`.**
5. Backspace then Tab as fast as your fingers go, ten times over.
   **Tab finishes the syllable or moves focus; never a stray jamo.**
6. Tab then at once Backspace, then Tab on what shows.
   **The word comes out right: `다으` becomes `다음`, not `다으 날`.**
7. Hold left Shift and Tab on a ghost, keep holding a moment; again with right Shift, on a ghost with `ㅆ` or `ㅃ` if you can.
   **The whole suggestion both ways, no wrong characters.**
8. Caps Lock on, then Tab, then Shift-Tab, then Caps Lock off.
   **The same characters as with it off. If Caps Lock switches you to ABC, just say so.**
9. With a ghost up, click the search field and Tab at once; again with Cmd-Tab away and back.
   **Tab is that field's or app's; never the ghost's text in the wrong place.**
10. Type through a long ghost at full speed, letter for letter.
    **It moves with you, no strobing. If it flashes, tell me: `Watcher.oneFrame` is too short for Chromium.**
11. Tab, then at once Return.
    **The word is in the sent message, and no ghost on the emptied composer.**

## ego lite, Korean: about 2 minutes
12. In a search box, repeat 1 to 3.
    **The same as T3. No ghost is the right failure; a misplaced ghost or a wrong character isn't.**
13. In Gmail compose, repeat 1 to 3.
    **The same as step 12.**
14. Type in a password field.
    **Never a ghost.**

## T3 composer, English: about 2 minutes
15. Switch to ABC, type `Can you take a look at`, and pause.
    **Grey text from the caret, on the baseline, the same size as your text.**
16. Tab, then Shift-Tab, then on a new ghost type the letters it shows.
    **One word, then all of it, then it shrinks and never lags the caret.**
17. With a ghost up, scroll the conversation; on the next, press Esc; on the next, move the window.
    **Gone at once each time, and Tab is T3's.**
18. With no ghost showing, press Tab.
    **T3 gets it as usual.**

## The window: about 2 minutes
W1. Type in its field, and Tab on the grey text. Paste with Cmd-V.
    **The same as in any app.**
W2. Press the power button, type, press it again. Then the sidebar icon: Apps, add an app, remove it; General, Start at Login on, then off.
    **No ghost while off. The login switch keeps what you set, and System Settings shows Itda under Login Items only while it's on.**
W3. Models: Get Kanana 1.5, stop it with ✕, Get it again, wait, Use it, type, then Use Qwen 3.5 0.8B.
    **The second Get resumes. The pill in the field names the model in use, and suggestions keep working after each switch.** Click the pill: **the list opens at once, marks the model in use, and closes on a click outside or Esc.**
W4. Close the window, then open Itda from Finder or the menu.
    **The Dock icon goes with the window. The same window comes back, and Itda kept working between.**

## The rest: about 1 minute
19. Menu: "Pause in T3", type, unpause; turn Itda off, type, turn it on.
    **No ghost and a normal Tab each time.**
20. In TextEdit in dark mode, repeat 1.
    **A readable grey ghost.**
21. Quit Itda from the menu.
    **No crash report.**
