# Itda (잇다)

Inline typing suggestions for your whole Mac, in Korean and English, with a model that runs on your machine.

![Itda suggesting the rest of a Korean sentence](Tests/screenshots/korean-light.png)
![Itda suggesting the rest of an English sentence](Tests/screenshots/light.png)

The grey text is the suggestion. Nothing is inserted until you press Tab. *Itda* means "to continue, to join".

## Install

You need macOS 26 and Swift 6.2 (Xcode 26). There is no download yet.

```sh
git clone https://github.com/hrsong99/itda
cd itda
scripts/build-app.sh
```

Move `build/Itda.app` to Applications and open it. Grant Accessibility when asked. The app lives in the menu bar and fetches its 1.4 GB model once.

## Use

| Key | What it does |
|---|---|
| **Tab** | Takes the next word |
| **Shift-Tab** | Takes the whole suggestion |
| **Esc** | Hides the suggestion, so Tab moves between fields again |

Or keep typing: the suggestion follows along while you match it. With no suggestion showing, these keys do what they always do. The menu pauses Itda for the current app, or turns it off, and takes any other GGUF model.

## Why it's different

Most tools in this category go quiet while you compose Hangul, or suggest from a half-built syllable. We read the source of [66 open-source projects](docs/audit.md) and found none that completes through a composing syllable. Three things do the work:

**It won't guess at the half-typed word.** The prompt stops at the last whole word and the model has to reproduce what you've typed so far. Across 130 paired mid-word English positions on a Gemma model, a useful suggestion went from 7.7% to 50.8%. The shipped mask on the default model wasn't compared this way.

**It stays quiet when the model isn't sure.** Itda shows a suggestion only if the first word's probability, among words that fit what you've typed, clears one threshold. On 2,400 held-out English requests with the default model, 84.9% of the suggestions shown were right (919 of 1,082; 82-88%, by thread), at 45.1% coverage. With no gate, 50-53% were right. Wrong suggestions fell from 44-46% of requests to 6.8%.

**It finishes Korean with real key presses.** The syllable you're composing stays out of the prompt, the model's output must fit its 2-set keys (so `하` allows `한` or `함`), and Tab presses the remaining keys so the input method finishes the syllable itself. On 1,099 requests mid-syllable in public Korean text, keystrokes saved per request went from 0 when sending the syllable to the model to 0.69. It costs more wrong suggestions: 18.2% of those requests, against 8.4%.

Across whole messages, replayed with real typing delays, that saves **22.8% of keystrokes in English** (1,200 keys) and **8.8% in Korean** (1,200 keys of public text), or 13.4% on 70 of the author's own messages. A match has to be exact, so a good paraphrase scores zero. The English messages are the author's and aren't published. Method and more numbers: [docs/measuring.md](docs/measuring.md). The design: [docs/how-it-works.md](docs/how-it-works.md).

## What it costs

Measured on an M5 with 16 GB, running the real app path on a test window with `scripts/e2e.sh --measure`. [Details](docs/measuring.md).

| State | Memory |
|---|---|
| Typing, and for 15 s after | about **1.5 GB wired**, plus 250-310 MB of footprint |
| Stopped, model still loaded, up to 5 minutes | 250 MB footprint, nothing wired |
| Unloaded, after 5 idle minutes | **79 MB** |

Wired memory is what counts: nothing else can use it, and Activity Monitor's per-app number leaves it out. Look at its Wired line.

- **Disk:** a 1.4 GB model and an app of about 27 MB.
- **CPU:** 0.13-0.27% of a core idle over 60 s. 7-8% while typing about 5 keys a second.
- **Speed:** a suggestion's first displayable word arrives in 60 ms in English and 102 ms in Korean (p50, requests that got that far, timed replay). No model call at all on 48% of English keys and 27% of Korean, because the suggestion still fits.
- **Power:** not measured.

## Privacy

- **One permission: Accessibility.** The app asks for nothing else, and it never uses Screen Recording.
- **What it reads:** the focused field and text near it in the window, to give the model context. A key tap watches for Tab, Shift-Tab and Esc, and it sees your other keys so it can track Korean composition. All of it stays in memory.
- **What it writes:** the on/off switch, your paused apps and a custom model's path as settings, and the model file in Application Support. Nothing with typed text, and no logs.
- **Network:** one URL, the model on Hugging Face, checked by SHA-256. Nothing else, ever. With your own model it doesn't connect at all.
- **Secure fields** are skipped: Itda doesn't read them or suggest in them.

## Limits

- **macOS 26 or later.** Only tested on Apple Silicon, on one M5.
- **Korean accept needs Apple's 2-Set Korean layout.** With another Korean layout, Itda shows nothing after a Hangul character, because a composition could swallow what it inserts.
- **Korean is the weak spot.** The accuracy figures come mostly from public dialogue text. There, about a third of Korean suggestions shown match exactly (31-34%) and raising the threshold doesn't help; about half of the wrong ones are near misses. English is much better.
- **No suggestion with text after the caret.** Itda only continues at the end of a field's text.
- **No Developer ID, so no notarization.** Build it yourself and this won't come up. A build downloaded from someone else gets a Gatekeeper warning. Without a stable signing identity on your Mac, each rebuild asks for Accessibility again.

## Status

Version 0.1. Unit tests cover the logic, and `scripts/e2e.sh` checks the app against a private window, including every composing state of 17 hard words through the live 2-set input method in a native field.

<!-- LIVE-TEST --> T3 Code and ego lite verification results will go here. Until then, Chromium-based apps are unverified: [docs/live-test.md](docs/live-test.md) is the checklist.

## More

- [How it works](docs/how-it-works.md)
- [How the numbers were measured](docs/measuring.md)
- [What 66 open-source projects taught us](docs/audit.md)
- [Credits](CREDITS.md). The ideas are from many people; every one is named there.
- [MIT licence](LICENSE)

## 한국어 요약

잇다는 한국어와 영어를 쓰는 사람을 위한 macOS 인라인 자동완성 앱입니다. 모델은 내 Mac에서만 돌아갑니다.

- **사용법:** 회색 글자가 제안입니다. Tab은 다음 단어, Shift-Tab은 전체, Esc는 닫기입니다.
- **다른 점:** 조합 중인 글자를 모델에 보내지 않고, 두벌식 키 입력에 맞는 결과만 받습니다. Tab을 누르면 남은 키를 실제로 눌러 입력기가 글자를 마저 조합합니다.
- **비용:** 입력 중과 그 후 15초 동안 약 1.5 GB를 점유하고(wired), 5분 쉬면 79 MB로 줄어듭니다. 모델은 처음 한 번 1.4 GB를 받습니다.
- **개인정보:** 손쉬운 사용 권한만 씁니다. 모델 다운로드 외에는 네트워크를 쓰지 않고, 입력한 글을 저장하지 않으며, 비밀번호 칸은 건너뜁니다.
- **한계:** macOS 26 이상과 두벌식이 필요합니다. 한국어 정확도는 영어보다 낮습니다. 공개 대화 데이터에서 보여 준 제안의 31-34%가 정확히 일치했고, 전체 메시지 기준으로 키 입력을 8.8% 줄였습니다. Developer ID가 없어 내려받은 빌드에는 Gatekeeper 경고가 뜹니다.
