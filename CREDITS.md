# Credits

No code was copied into ItdaCore. It is an original implementation, and these are the ideas it stands on.
"Idea only" repos are under licences or terms that rule out copying, so nothing but the idea was taken from them.

| Idea in the core | Source | Licence |
|---|---|---|
| Hold out the half-typed word so the prompt stays byte-identical inside a word | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype), [kolganovr/halfword](https://github.com/kolganovr/halfword) | MIT or Apache-2.0; MIT |
| Force the fragment back with a one-line GBNF grammar | [lyx-27/ABC-Plus](https://github.com/lyx-27/ABC-Plus) | MIT |
| Prompt ends at a word with no trailing space, as the next token carries its own | [kolganovr/halfword](https://github.com/kolganovr/halfword), [menufactory43/Souffleuse](https://github.com/menufactory43/Souffleuse) | MIT; no licence file, idea only |
| Raw continuation, no chat template | [nikiomori/Pretype](https://github.com/nikiomori/Pretype), [r3dbars/tilde](https://github.com/r3dbars/tilde) | MIT |
| Window start that moves in steps, to keep the cached head | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype), [johannes-kaindl/ghostline](https://github.com/johannes-kaindl/ghostline), [stevyhacker/LokalBot](https://github.com/stevyhacker/LokalBot) | MIT or Apache-2.0; AGPL-3.0, idea only; GPL-3.0, idea only |
| Gate on the first word's probability from the logits, conditional on fitting what was typed | [nilava/TabType](https://github.com/nilava/TabType), [nikiomori/Pretype](https://github.com/nikiomori/Pretype), [kolganovr/halfword](https://github.com/kolganovr/halfword), [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim) | MIT; MIT; MIT; Apache-2.0 |
| Byte-level matching, as tokens can split a character | [nilava/TabType](https://github.com/nilava/TabType), [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | MIT; MIT or Apache-2.0 |
| Type-through decided by comparing field text, not key events | [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim), [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | Apache-2.0; MIT or Apache-2.0 |
| Accept the next word or everything | [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype), [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim) | MIT or Apache-2.0; Apache-2.0 |
| Replay testing without a model | [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim), [nilava/TabType](https://github.com/nilava/TabType) | Apache-2.0; MIT |

Constrained fragments were also seen in [menufactory43/Souffleuse](https://github.com/menufactory43/Souffleuse) and
[mshll/ghostwriter](https://github.com/mshll/ghostwriter) (GPL-3.0), ideas only.

Grammar syntax and the engine it targets: [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp), MIT.
Hangul decomposition follows the Unicode Standard's syllable formula.

Not found in any audited project: withholding a composing Hangul syllable and matching it by 2-set keystrokes.

## The macOS app

No code was copied into ItdaApp either. These are the ideas it uses.

| Idea in the app | Source | Licence |
|---|---|---|
| Insert with `keyboardSetUnicodeString` in short chunks, never splitting a surrogate pair, with no clipboard | [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist), [nikiomori/Pretype](https://github.com/nikiomori/Pretype) | MIT; MIT |
| Mark our own events so the key tap lets them pass | [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist), [nikiomori/Pretype](https://github.com/nikiomori/Pretype) | MIT; MIT |
| The AX text marker attributes for caret rects and page text in Chromium | [johannes-kaindl/ghostline](https://github.com/johannes-kaindl/ghostline), [stevyhacker/LokalBot](https://github.com/stevyhacker/LokalBot) | AGPL-3.0, idea only; GPL-3.0, idea only |

The default model, [Kanana 1.5 2.1B base](https://huggingface.co/mradermacher/kanana-1.5-2.1b-base-GGUF), is by Kakao, quantised by mradermacher.
