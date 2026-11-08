# Credits

No code was copied into HalftypeCore. It is an original implementation, and these are the ideas it stands on.
"Idea only" repos are under licences or terms that rule out copying, so nothing but the idea was taken from them.

| Idea in the core | Source | Licence |
|---|---|---|
| Hold out the half-typed word so the prompt stays byte-identical inside a word | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype), [kolganovr/halfword](https://github.com/kolganovr/halfword) | MIT or Apache-2.0; MIT |
| Force the fragment back: a one-line GBNF grammar there, a mask on the logits here | [lyx-27/ABC-Plus](https://github.com/lyx-27/ABC-Plus) | MIT |
| Prompt ends at a word with no trailing space, as the next token carries its own | [kolganovr/halfword](https://github.com/kolganovr/halfword), [menufactory43/Souffleuse](https://github.com/menufactory43/Souffleuse) | MIT; no licence file, idea only |
| Raw continuation, no chat template | [nikiomori/Pretype](https://github.com/nikiomori/Pretype), [r3dbars/tilde](https://github.com/r3dbars/tilde) | MIT |
| Window start that moves in steps, to keep the cached head | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype), [johannes-kaindl/ghostline](https://github.com/johannes-kaindl/ghostline), [stevyhacker/LokalBot](https://github.com/stevyhacker/LokalBot) | MIT or Apache-2.0; AGPL-3.0, idea only; GPL-3.0, idea only |
| Gate on the first word's probability from the logits, conditional on fitting what was typed | [nilava/TabType](https://github.com/nilava/TabType), [nikiomori/Pretype](https://github.com/nikiomori/Pretype), [kolganovr/halfword](https://github.com/kolganovr/halfword), [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim) | MIT; MIT; MIT; Apache-2.0 |
| Byte-level matching, as tokens can split a character | [nilava/TabType](https://github.com/nilava/TabType), [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | MIT; MIT or Apache-2.0 |
| Type-through decided by comparing field text, not key events | [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim), [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | Apache-2.0; MIT or Apache-2.0 |
| Compare the field's text to reuse a suggestion, again with no key events | [mekanismvibe/opentypist](https://github.com/mekanismvibe/opentypist), [Fedotoff-Alex/dopishi](https://github.com/Fedotoff-Alex/dopishi) | MIT; MIT |
| Keep a sliding-window cache trimmable with `swa_full`, and ask the model what it can do rather than keep a table | [nilava/TabType](https://github.com/nilava/TabType), [whoisjson0/typer](https://github.com/whoisjson0/typer) | MIT; MIT |
| Accept the next word or everything | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype), [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim) | MIT or Apache-2.0; Apache-2.0 |
| Replay testing without a model | [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim), [nilava/TabType](https://github.com/nilava/TabType) | Apache-2.0; MIT |

Constrained fragments were also seen in [menufactory43/Souffleuse](https://github.com/menufactory43/Souffleuse) and
[mshll/ghostwriter](https://github.com/mshll/ghostwriter) (GPL-3.0), ideas only.

Hangul decomposition follows the Unicode Standard's syllable formula.

Withholding a composing Hangul syllable, matching it by 2-set keystrokes, and accepting by letting the input method finish it from real key
events are Halftype's own. We found no earlier version in the 66 projects we read, by searching their source; none was tested live in Korean.

## The macOS app

No code was copied into HalftypeApp either. These are the ideas it uses.

| Idea in the app | Source | Licence |
|---|---|---|
| Insert with `keyboardSetUnicodeString` in short chunks, never splitting a surrogate pair, with no clipboard | [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist), [nikiomori/Pretype](https://github.com/nikiomori/Pretype) | MIT; MIT |
| Mark our own events so the key tap lets them pass | [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist), [nikiomori/Pretype](https://github.com/nikiomori/Pretype) | MIT; MIT |
| Stop while Secure Input is on, and say so in the menu | [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist), [nilava/TabType](https://github.com/nilava/TabType) | MIT; MIT |
| Esc on a ghost hides it and goes no further | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype), [nilava/TabType](https://github.com/nilava/TabType), [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist) | MIT or Apache-2.0; MIT; MIT |
| Check `isOnActiveSpace`, and hide on sleep, lock and session change | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | MIT or Apache-2.0 |
| Take the tap down on the permission's Darwin notification, as `AXIsProcessTrusted` can be stale after a revoke | [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos), [chromium/chromium](https://github.com/chromium/chromium) | GPL-3.0, idea only; BSD-3-Clause |
| Wake Chromium and Electron accessibility once per process, by what the bundle is built on, not under VoiceOver; set Chromium's flag again only past its 2 s wait, and clear it at quit only where we set it | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | MIT or Apache-2.0 |
| Map the caret through the newlines Chromium's ranges leave out between paragraphs, and read nothing if they don't line up | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | MIT or Apache-2.0 |
| Record why there's no suggestion, and say it in one line | [nikiomori/Pretype](https://github.com/nikiomori/Pretype), [Fedotoff-Alex/dopishi](https://github.com/Fedotoff-Alex/dopishi) | MIT; MIT |
| A menu-bar icon that dims when off, shows a download's percentage, and marks a problem | [nilava/TabType](https://github.com/nilava/TabType), [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist), [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | MIT; MIT; MIT or Apache-2.0 |
| A first-run line that teaches the keys, then confirms the first accept | [nikiomori/Pretype](https://github.com/nikiomori/Pretype) | MIT |
| Say when macOS's own inline predictions are on, and link to the setting rather than change it | [mshll/ghostwriter](https://github.com/mshll/ghostwriter) | GPL-3.0, idea only |
| Delete a downloaded model, and an Uninstall section in the README | [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist), [nikiomori/Pretype](https://github.com/nikiomori/Pretype), [mekanismvibe/opentypist](https://github.com/mekanismvibe/opentypist), [mshll/ghostwriter](https://github.com/mshll/ghostwriter) | MIT; MIT; MIT; GPL-3.0, idea only |
| The AX text marker attributes for caret rects and page text in Chromium | [johannes-kaindl/ghostline](https://github.com/johannes-kaindl/ghostline), [stevyhacker/LokalBot](https://github.com/stevyhacker/LokalBot) | AGPL-3.0, idea only; GPL-3.0, idea only |

## What it runs on and was measured with

| What | Source | Licence | Note |
|---|---|---|---|
| Inference engine, linked as a pinned xcframework (b12167) | [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) | MIT | Its licence ships in the app, from `scripts/llama.cpp-LICENSE` |
| Automatic updates, linked and shipped in the app | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) | MIT and others, in `Sparkle-LICENSE` in the app | |
| Default model, Gemma 4 E2B, by Google | [google/gemma-4-E2B](https://huggingface.co/google/gemma-4-E2B) | Apache-2.0 | Not in this repo. Downloaded on first run |
| The GGUF the app downloads, by mradermacher | [mradermacher/gemma-4-E2B-GGUF](https://huggingface.co/mradermacher/gemma-4-E2B-GGUF) | Apache-2.0 | Q4_K_M, checked by SHA-256 |
| Optional models, Qwen 3.5 0.8B and 2B, by Alibaba's Qwen team | [Qwen/Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B) | Apache-2.0 | Not in this repo. Downloaded if you pick one |
| The GGUFs of Qwen 3.5 0.8B and 2B, by Unsloth | [unsloth/Qwen3.5-0.8B-GGUF](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF), [unsloth/Qwen3.5-2B-GGUF](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF) | Apache-2.0 | Q4_K_M, checked by SHA-256 |
| Optional model, Kanana 1.5 2.1B base, by Kakao | [kakaocorp/kanana-1.5-2.1b-base](https://huggingface.co/kakaocorp/kanana-1.5-2.1b-base) | Apache-2.0 | Not in this repo. Downloaded if you pick it |
| The GGUF the app downloads, by mradermacher, from [OpenLLM-Korea's copy](https://huggingface.co/OpenLLM-Korea/kanana-1.5-2.1b-base) | [mradermacher/kanana-1.5-2.1b-base-GGUF](https://huggingface.co/mradermacher/kanana-1.5-2.1b-base-GGUF) | Apache-2.0 | Q4_K_M, checked by SHA-256 |
| Public Korean text used to measure accuracy | [smilegate-ai/korean_smile_style_dataset](https://github.com/smilegate-ai/korean_smile_style_dataset) | CC BY-NC 4.0 | Used for measuring only. None of it is in this repo or the app |

The window's look, one field and a lot of white, takes its idea from [Ollama's desktop app](https://ollama.com/blog/new-app). No code or assets from it.

The model makers' marks in the Models list (`Sources/HalftypeApp/Logos`): Qwen's and Gemma's from [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) (`@lobehub/icons-static-svg` 1.70.0, MIT), turned into PDF; Kakao's from its [Hugging Face avatar](https://huggingface.co/kakaocorp). The marks are Alibaba's, Google's and Kakao's, shown only beside their own models.

The icon was made with Codex's built-in image tool: prompts and outputs in [docs/icon](docs/icon/README.md).

Every GitHub link and licence here was checked with `gh repo view` and the repo's licence file, and every model licence on its Hugging Face card, on 2026-11-07. [docs/audit.md](docs/audit.md) credits all 66 projects we read.
