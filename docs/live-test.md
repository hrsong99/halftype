# Live test, by hand

What the automatic checks can't reach: the real Tab in real apps, and Korean in Chromium. Most important first; each step is what to do, then **what should happen**. Stop when your 10 minutes are up: what's left matters least.
Any wrong character: tell me what you typed and what came out. Use a new, empty T3 thread, as step 11 sends a message.

## Before you start (the first time, wait for a 0.5 GB download; it isn't part of the 10 minutes)
A. Quit Cotypist, which also takes Tab, and any other app that reads your screen through Accessibility, such as Raycast or Wispr Flow. Then quit and reopen T3 and ego lite, so the accessibility switches they turned on are off.
   **Cotypist's icon is gone from the menu bar, and both apps are back.**
B. Open `build/Halftype.app`; its window asks for Accessibility. Press the button and grant it.
   **No system dialog before you press the button. Before the grant the download already shows under the button, with its size and "You can close this window." Within 2 s of the grant Halftype comes back in front of System Settings and shows its field, with no restart. Never a prompt for Input Monitoring.**
   Once the model is ready, don't type: **the field holds "Please let me know if you have any" (or a Korean sentence, if a Korean source is on) with a ghost after it, and under it "Tab takes a word. Shift-Tab takes it all. Esc hides it."** Press Tab: **the word goes in, and the line becomes "That's it. Halftype works like this in almost any app." with a Start at Login button.** Press it: **the button goes, and General shows Start at Login on.** Turn it back off there if you don't want it.
C. Once the model is ready, and before anything else touches ego lite: click its address bar or a search box, type `Can you take a look at`, pause, and keep typing slowly for a few seconds if nothing shows.
   **A ghost within about 3 s, with nothing else running that could have woken ego lite's accessibility.** Then in Terminal, `osascript -e 'tell application "System Events" to get value of attribute "AXEnhancedUserInterface" of application process "Finder"'`: **false**, as Halftype leaves native apps alone. If ego lite never shows a ghost, say so: that's the case this step is for.

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
13. In Gmail compose, repeat 1 to 3. Then press Return for a second paragraph and type a few words there; again on a third.
    **The same as step 12, and ghosts in the second and third paragraphs too, continuing what you typed there, not the line above.**
14. Type in a password field.
    **Never a ghost.**

## T3 composer, English: about 2 minutes
15. Switch to ABC, type `Can you take a look at`, and pause.
    **Grey text from the caret, on the baseline, the same size as your text.**
16. Tab, then Shift-Tab, then on a new ghost type the letters it shows.
    **One word, then all of it, then it shrinks and never lags the caret.**
17. With a ghost up, scroll the conversation; on the next, press Esc; on the next, move the window.
    **Gone at once each time, and Tab is T3's. Esc does nothing else in T3.**
18. With no ghost showing, press Tab.
    **T3 gets it as usual.**
19. Shift-Return to start a second line, then type `and then we can`; once more on a third line.
    **A ghost at the caret on each line, continuing that line.**
20. Press Cmd-= twice, type a few words, and pause. Then Cmd-0.
    **The ghost grows with the text, about the size of your letters, on their baseline. After Cmd-0 it's back to normal.**

## When it must stand aside: about 4 minutes
T1. The permission, each way. No automatic test reaches this: they stand in for the system. Write down a result for each of a, b and c.
    Before each, run `(sleep 45; pkill -9 -x Halftype) &` in Terminal, as a tap left in place can hold every click and key. If Halftype is killed at 45 s, reopen it and say which step: the tap didn't come down.
    a. First grant: step B, on a Mac where Halftype has no row yet. **No system dialog before the button; the field within 2 s of the grant.**
    b. Turn Halftype off under Privacy & Security, Accessibility, and click around. **Clicks and keys work within a second. The window offers Allow Accessibility, the menu says it's waiting, and no system dialog appears, once or over and over.** Turn it back on. **The field within 2 s, and Tab takes a ghost.**
    c. Remove the row with `-`, click around, and add Halftype back. **The same as b, each way.**
T2. Secure Input. Turn on Terminal's Secure Keyboard Entry, then type in T3. Don't run `scripts/e2e.sh` meanwhile.
    **No ghost, Tab is T3's, the menu says Secure Input is on, and the menu-bar icon has a dot.** Turn it off and type: **ghosts are back, the menu line says "Working.", and the dot is gone.**
T3. In a search field that Esc clears, type until a ghost shows, and press Esc. Press it again.
    **The first hides the ghost and leaves your text. The second clears the field. Cmd-Option-Esc with a ghost up still opens Force Quit.**
T4. Narrow T3's window until a long ghost is cut off at the field's edge. Shift-Tab; on another, Tab as fast as you can; and the same in Korean.
    **Exactly the words you could see, never more, then Tab is T3's until the rest is drawn.**
T5. With a ghost up, lock with Ctrl-Cmd-Q and unlock; then close the lid and open it; then unplug a display, if you have one.
    **Gone each time, and Tab is T3's. Typing brings ghosts back, and Tab takes them.**

## The window: about 2 minutes
W1. Type in its field, and Tab on the grey text. Paste with Cmd-V.
    **The same as in any app.**
W2. Press the power button, type, press it again. Then scroll down: the card slides in with the settings. Click Apps in it, add an app, remove it; General, Start at Login on, then off. The sidebar icon hides the card, and again shows it, at any scroll.
    **No ghost while off. The login switch keeps what you set, and System Settings shows Halftype under Login Items only while it's on.**
W3. Models: Get Kanana 1.5, stop it with ✕, Get it again, wait, Use it, type, then Use Qwen 3.5 0.8B.
    **The second Get resumes. The pill in the field names the model in use, and suggestions keep working after each switch.** Click the pill: **the list opens at once, marks the model in use, and closes on a click outside or Esc.**
W4. Close the window, then open Halftype from Finder or the menu.
    **The Dock icon goes with the window. The same window comes back, and Halftype kept working between.**
W5. Quit Halftype, move `kanana-1.5-2.1b-base.Q4_K_M.gguf` out of `~/Library/Application Support/Halftype`, turn Wi-Fi off, and open Halftype. Turn Wi-Fi on. Mid-download, turn it off again until the line changes, then on, and press Retry. At about half, quit and reopen. Move the model back after, if it didn't finish.
    **"Waiting for a connection", then it starts by itself. The drop shows a failure line with Retry, in the window and in the menu, within a minute. Retry and the reopen both carry on from where it was, not from 0.**

W6. Why there's no ghost. In T3, type with text after the cursor and open the menu; then in a plain field type and pause until no ghost comes, and open the menu.
    **"Text after the cursor, so no suggestion here." Then "Working. Not sure enough to suggest yet." The window's field shows the same lines, without flickering as you type.**
W7. Turn on System Settings, Keyboard, Text Input, Input Sources, Edit, "Show inline predictive text". Open the window and the menu.
    **The window says macOS shows its own grey predictions too, and the menu offers Turn Off macOS Predictions; each opens Keyboard settings.** Turn the setting back off: **both go.**
W8. Models: Delete on a model you have and aren't using.
    **It goes back to Get, and the file is gone from `~/Library/Application Support/Halftype`. The model in use has no Delete.**

## The rest: about 1 minute
21. Menu: "Pause in T3", type, unpause; turn Suggestions off, type, turn it on.
    **No ghost and a normal Tab each time, and the menu-bar icon dimmed while paused or off. Paused in T3, it's back to full when another app is in front.**
22. In TextEdit in dark mode, repeat 1.
    **A readable grey ghost.**
23. Quit Halftype from the menu. Then in Terminal, the command from step C with `"ego lite"` in place of `"Finder"`.
    **No crash report, and `false`: the switch Halftype turned on in ego lite is back off.**
