# Typing comparison: Halftype against the apps people use

Halftype, Cotypist, Cotabby, KeyType and macOS's own inline predictions, each with its default model, typed into the same field
with the same public sentences at the same human delays, and judged from the screen: what any user would see. One app runs at a time.
It feeds the comparison on the landing page (`docs/site/compare/`, branch `landing-page`, which has the at-rest numbers).

## Run it

```sh
bench/compare/run.sh --check    # the preconditions only: types nothing, launches nothing
bench/compare/run.sh            # everything, about 45-50 minutes
bench/compare/run.sh --apps halftype,keytype --en 16 --ko 10
```

It takes the keyboard, the pointer and the front window the whole time and switches input sources, so start it when you leave the Mac.
It stops by itself if anything other than the app under test takes the window, and Ctrl-C in its terminal stops it too; either way it
quits the app it started, puts back the input source and Halftype's settings. Results go to `~/halftype-lab-private/compare/<time>/`.
Only `summary.md` from there belongs in the repo, as `bench/compare/results/<date>.md`; the rest holds sentence IDs, per-key timings
and OCR crops of public text, and stays out.

### Preconditions, all checked and printed before anything is typed

1. **Your terminal** has Accessibility (to send keys and clicks) and Screen Recording (to read the field). The harness runs from the
   terminal, so macOS asks about the terminal. Screen Recording is for this tool only: Halftype itself never uses it.
2. **2-Set Korean** and ABC (or U.S.) are input sources.
3. **No autocomplete app is running**: no Halftype (a dev build from another session counts: ask it to stop, don't kill it), Cotypist,
   Cotabby, KeyType or Itda. Two apps fight over the same keys.
4. **Each app has Accessibility.** Halftype and Cotypist are in /Applications and have it. **Cotabby and KeyType need a Touch ID grant**:
   System Settings > Privacy & Security > Accessibility > + > `~/halftype-lab-private/rivals/Cotabby.app` and `KeyType.app` (the
   notarized release builds, copied there from their DMGs). `--check` reads the TCC database when the terminal has Full Disk Access;
   otherwise the warm-up finds out.
5. **Each app's default model is downloaded**: Halftype's Qwen 3.5 0.8B; Cotabby's and KeyType's are in their Application Support folders.
6. Halftype runs at its defaults (Long, Always, Qwen 3.5 0.8B, personal model off) whatever you have set; your settings come back when it quits.
7. **Cotypist**: if a personal prompt is set in its settings, its numbers include it (`--check` says so). Clear it for a default run.
   Its free plan has a daily cap; if suggestions stop part-way, the run prints a warning.

## What it does

For each app: launch it hidden (`open -g -j`), wait until a `.gguf` is mapped (`vmmap`), bring the test window forward with a click,
type the warm-up sentence twice and refuse to record unless a ghost was read at least once. **An app without its permissions may not be
running at all** (KeyType starts its engine only with Accessibility), which is why both checks gate every app. Then English, then Korean on
2-Set, then quit it and wait until its processes are gone.

- **The field** is this process's own `NSTextView`: one line of 17-point system text, black on white, caret drawn clear, no spelling
  correction or substitutions. macOS's predictions are on in it for the `macos` run only. It is cleared between sentences, so no app has
  context beyond the sentence.
- **Keys** are real HID events (`CGEvent` at `cghidEventTap`), so every app's event tap and the input method see them as typed.
  Delays are log-normal with the 264 ms median of measuring.md's typing histogram (sigma 0.5, 90-1200 ms), seeded by sentence, so every
  app gets the same pauses. After every third word the pause is a 1.5 s **probe**, so a slow app's speed is measured rather than cut off.
- **The screen**: ScreenCaptureKit streams the field's line at up to 60 Hz, cursor hidden, every app's overlay included. Nothing is typed
  right of the caret, so any ink there (darker than 232 of 255) is a suggestion, whatever colour each app draws it. Frames carry the
  time they were shown.
- **Reading a ghost**: the ink right of the caret, made black on white, read by Vision (`.accurate`, no language correction; Korean and
  English for the Korean run). A gap of over 0.2 em between caret and ink is a typed space.
- **The oracle** presses Tab only when what Tab takes is the true text and saves at least one key over the Tab itself: the first word
  for Halftype, Cotypist, Cotabby and KeyType (their default; Cotypist's partial accept is Tab), the whole prediction for macOS. While a
  syllable composes, a ghost may follow it or finish it (Halftype's way); both are tried. **Everything is scored from the field's own
  text, not from OCR**: a Tab that put in the wrong text is counted, the field is set back to where it went wrong, and the backspaces a
  user would need are charged.

## The numbers, per app and language

| Column | What it is |
|---|---|
| Keys saved | 1 - keys pressed (letters or 2-set keystrokes, Tabs, backspaces after a wrong Tab) / keys the sentence needs. 95% bootstrap CI over sentences |
| Keys with a ghost | Share of keys after which a ghost was on screen when the next key was due |
| First word right | Of those, the ghost's first word was the true next word, ending where it ends (`lo` is not right for `lot`) |
| Ghost after a key, fresh | Keystroke to the first frame with a new ghost, for keys pressed with no ghost on screen, if it came before the next key: p50, p90 |
| 1.5 s probe | At the probe pauses with no ghost before: the share where none came within 1.5 s, and p50 of the rest. The uncensored speed |
| Mid-syllable ghost | Korean: of keys that left a syllable composing, the share after which a new ghost appeared and was on screen |
| Tabs, wrong, as OCR read | Tabs pressed, Tabs that put in the wrong text, and Tabs whose result was exactly what the OCR said: how far to trust the OCR for that app |
| Footprint | `footprint -p` (phys_footprint) summed over the app's processes, sampled after each sentence: median and max |
| Model resident | Resident pages of mapped `.gguf` files (`vmmap`) at the end of a language: the weights, which footprint leaves out |
| CPU | CPU time of all the app's processes over wall time while typing a language, % of one core (`proc_pid_rusage`) |

## Limits

- **GPU memory per process isn't read**: nothing outside a process reports what Metal wired for it fairly across apps (Halftype's own
  `MTLDevice.currentAllocatedSize` in measuring.md is from inside). The resident `.gguf` pages stand in for the weights. macOS's
  predictions run in system processes, so they get no memory or CPU numbers at all.
- Small samples: 16 English and 10 Korean sentences per app (about 650 and 550 keys), to fit an hour. The CIs say how much that matters.
- **English**: Taskmaster-1 self-dialogs, the user side: people writing to a booking assistant, typed by crowd workers. Not chat
  between friends, and some words are rare. Sentences were kept only if every word is in the system dictionary. **Korean**: SmileStyle,
  other people's style-transfer dialogue (as in measuring.md), not how anyone writes messages.
- The order is fixed (macOS, Halftype, Cotypist, Cotabby, KeyType), so heat or other load drifts across apps. Run it with the Mac
  otherwise idle, and note what else was running.
- Latency is from the screen at 60 Hz: about ±17 ms per frame, and ScreenCaptureKit delivers a frame a few ms after it was shown.
  "Fresh" decides from the last frame received before the key, so a ghost that appeared in those few ms counts as not there.
- OCR can't be checked against a known ghost on another app's screen. What the run gives instead: the Tabs-as-read column, and the
  first 40 binarized crops per app with what OCR read (`crops/<app>/`) to check by eye. An app that draws a box or badge next to its ghost
  would show up there.
- Each app's Tab is taken as one word (macOS: all). If an app's Tab does something else, the wrong-Tab column shows it.
- Exact match only: a good paraphrase scores zero, the same for every app.
- Not tested: Chromium or Electron fields, other input methods, settings other than each app's defaults.

## Text

`ids.tsv` holds only IDs; `text.py fetch` downloads both sets at pinned commits, checks their SHA-256 and writes the sentences to
`~/halftype-lab-private/compare/text/` (`run.sh` does this when they're missing). `text.py select` shows how the IDs were picked
(seeded sample; typable on ABC or 2-set with no symbols beyond `,.?!'`; 30-70 characters in English, 14-40 in Korean; Korean from the
test dialogues of measuring.md's split). Licences are in CREDITS.md: Taskmaster-1 is CC BY 4.0, SmileStyle CC BY-NC 4.0, used for measuring only.

## Code

`Kit/` is the logic, tested offline with `swift test --disable-keychain -j 2 --filter CompareKitTests`: the oracle and key counting
(English, 2-set composing states), delays, scoring and intervals, and the ink finder and OCR on ghosts drawn the way an app draws them
(typed text in black, the ghost in grey from the caret, at two greys, English and Korean), including how quick a warm read is.
`Run/` drives the Mac and isn't unit-tested: only a real run shows it works. It's a target of the app's package because it borrows
HalftypeCore's Hangul keys and HalftypeApp's 2-set key table, as `Tests/e2e` does; it isn't part of the app.
