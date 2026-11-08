# What 66 open-source projects did well and badly

Before writing Halftype we read the core of 66 public projects that do local text completion: Mac apps, editor plugins, Linux and Windows tools, an Android keyboard and some research code. This is what we took from them, and what we learned to avoid.

**How to read this.** We read source code only, and built and ran nothing. Numbers marked *their number* are the project's own, not checked here. Each code link is pinned to the commit we read, in November 2026. A project named under a mistake often does something else very well, and many are young. These are notes on ideas, not a ranking of anyone's work. Projects can have changed since.

**66 projects aren't 66 sources.** Several are forks or ports, such as the Cotabby family, the KeyType family and the llama.vim line, and two are snapshots of one app. So when many agree, count the families rather than the repos.

## Top ideas, ranked by effect on suggestion quality and speed

Each idea is tagged with the part of the design it belongs to: prompt, context, inference, lifecycle, post-processing, CJK/IME, accept or tests. *Used* means it's in Halftype. See [CREDITS.md](../CREDITS.md).

1. **Hold the half-typed word out of the prompt, then force it back.** *Inference, used.* The prompt stays byte-identical while you type inside a word, and generation has to reproduce what you've typed. [`TabType: VocabIndex.swift:36`](https://github.com/nilava/TabType/blob/b75ea0e22bc565e57b133b2625a49d7e8a24c789/Sources/TabTypeKit/Inference/VocabIndex.swift#L36) and [`foretype: words.rs:23`](https://github.com/DaraSingh1998/foretype/blob/3ed7161e0851f4bf3260f90d09edee0e5eca6c1a/core/src/words.rs#L23) filter tokens by bytes; [`ABC-Plus: TextLogic.swift:50`](https://github.com/lyx-27/ABC-Plus/blob/a3044b18cdaed96a44126cfd318b8047570a79ca/Sources/TextLogic.swift#L50) does it with a one-line grammar. Souffleuse reports mid-word hit@1 going from 16-50% to 63-86% (*their number*, with a beam).
2. **Gate on the first word's probability, among the tokens that fit.** *Post-processing, used.* The model already knows how sure it is. [`foretype: engine.rs:1487`](https://github.com/DaraSingh1998/foretype/blob/3ed7161e0851f4bf3260f90d09edee0e5eca6c1a/core/src/engine.rs#L1487), [`Pretype: MLXEngine+Generation.swift:334`](https://github.com/nikiomori/Pretype/blob/ec05295664e2814a88e1b475801ce104a948c2cd/Sources/Pretype/Engines/MLXEngine+Generation.swift#L334), [`halfword: llm.py:169`](https://github.com/kolganovr/halfword/blob/2ce4289ac041c415fa6ead150dd0fb0e835d27ad/halfword/llm.py#L169), and [`tsugi.nvim: trim.lua:168`](https://github.com/MizuchiLabs/tsugi.nvim/blob/d4b3ca5ab64f4d310857e4906c740b5dc78810b2/lua/tsugi/trim.lua#L168), which also cuts and stops while streaming. On TabType's seed, gating and healing took precision from 0.297 to 0.66 (*their number*).
3. **Raw continuation: context first, the caret last, no chat wrapper.** *Prompt, used.* Everything else assumes it. [`Pretype: CompletionEngine.swift:53`](https://github.com/nikiomori/Pretype/blob/ec05295664e2814a88e1b475801ce104a948c2cd/Sources/Pretype/Engines/CompletionEngine.swift#L53).
4. **Keep the prompt's head still, and move the window start in steps.** *Inference, used.* This turns a key into a token or two of work. [`Typist: PromptBuilder.swift:88`](https://github.com/BrodySalvucci/Typist/blob/4c1e66f1b0c47972de17053a557818f7a666a60f/Sources/TypistCore/PromptBuilder.swift#L88), [`tilde: RawContinuationPrompt.swift:284`](https://github.com/r3dbars/tilde/blob/f36f6562b4c228e68027ac31855a817e7f85df5d/Sources/TildeCore/Engine/RawContinuationPrompt.swift#L284). Foretype records 12-25 ms warm against 293-833 ms cold ([`foretype: MEASUREMENTS.md:30`](https://github.com/DaraSingh1998/foretype/blob/3ed7161e0851f4bf3260f90d09edee0e5eca6c1a/docs/MEASUREMENTS.md#L30), *their number*).
5. **End the prompt at a word, with no trailing space.** *Prompt, used.* The next token brings its own space. [`halfword: llm.py:142`](https://github.com/kolganovr/halfword/blob/2ce4289ac041c415fa6ead150dd0fb0e835d27ad/halfword/llm.py#L142). casecomplete reports top-1 going from about 1% to 13% from this alone ([`casecomplete: main.rs:588`](https://github.com/drknowhow/casecomplete/blob/0569a1c908d00b0348ad75b5369b45846c531c59/crates/cc-app/src/main.rs#L588), *their number*).
6. **Reuse a suggestion by comparing the field's text, not key events.** *Lifecycle, used.* No model call, and it survives an input method. [`opentypist: Suggestion.swift:25`](https://github.com/mekanismvibe/opentypist/blob/2f341dc1d8a6c48ff4fae77829ae38885d8216b3/Sources/OpenTypist/Suggestion.swift#L25), [`dopishi: SuggestionReconcile.swift:44`](https://github.com/Fedotoff-Alex/dopishi/blob/d5736d790aa535ef1fd56a434d9316849dc14cec/Sources/DopishiCore/SuggestionReconcile.swift#L44), and in a running stream [`continue: GeneratorReuseManager.ts:29`](https://github.com/continuedev/continue/blob/5522c6f44ca0ac3528b37244818fbfa39b5af470/core/autocomplete/generation/GeneratorReuseManager.ts#L29).
7. **Keep text as bytes until it's complete.** *CJK/IME, used.* A token can split a Hangul character. [`ghostwriter: BeamSearch.swift:18`](https://github.com/mshll/ghostwriter/blob/53f2dc56ce193145d2b1cd13c5eb7f4914902a34/Packages/GhostwriterKit/Sources/Inference/BeamSearch.swift#L18) (idea only).
8. **Ask the model what it can do.** *Inference, used.* Read token attributes and cache abilities from the runtime and keep no per-model table. [`typer: llama_server.cpp:133`](https://github.com/whoisjson0/typer/blob/f6db9b4e1b33a2df820645f0d87fe273a54096ee/scripts/llama_server.cpp#L133), [`TabType: LlamaRuntime.swift:87`](https://github.com/nilava/TabType/blob/b75ea0e22bc565e57b133b2625a49d7e8a24c789/Sources/TabTypeKit/Inference/LlamaRuntime.swift#L87), [`cotabbyinference: CotabbyInferenceEngine.cpp:558`](https://github.com/FuJacob/cotabbyinference/blob/0db6b1f293e9c9e3fcc96a1ae26ebedc7745b239/Sources/CotabbyInferenceEngine/CotabbyInferenceEngine.cpp#L558).
9. **Ask the platform about composition.** *CJK/IME, part used.* Marked ranges in native fields ([`opentypist: FocusReader.swift:145`](https://github.com/mekanismvibe/opentypist/blob/2f341dc1d8a6c48ff4fae77829ae38885d8216b3/Sources/OpenTypist/FocusReader.swift#L145)), including the zero-length quirk ([`foretype: FocusTracker.swift:454`](https://github.com/DaraSingh1998/foretype/blob/3ed7161e0851f4bf3260f90d09edee0e5eca6c1a/mac/Sources/Foretype/FocusTracker.swift#L454)), and the marker-range attribute for Chromium ([`LokalBot: CotypingAXHelper.swift:36`](https://github.com/stevyhacker/LokalBot/blob/e7235599ad520c8fd8ff493244050fe8c839f129/LokalBot/Cotyping/CotypingAXHelper.swift#L36), idea only).
10. **Read the conversation above the field.** *Context, used in a simple form.* [`tilde: RawContinuationPrompt.swift:521`](https://github.com/r3dbars/tilde/blob/f36f6562b4c228e68027ac31855a817e7f85df5d/Sources/TildeCore/Engine/RawContinuationPrompt.swift#L521), [`pluma: ConversationContext.swift:345`](https://github.com/SLatz18/pluma/blob/72b15dba97f99764a921c1d5c3585c45f7becb66/Pluma/Services/ConversationContext.swift#L345), and by geometry [`ghosttab: context.py:115`](https://github.com/TheKerbecs/ghosttab/blob/3da291248c97a3ab19f903ea570cd51b1828d932/ghosttab/context.py#L115) (idea only).
11. **Measure by replay, tuning on some data and testing on the rest.** *Tests, used.* Tune a floor without the model ([`tsugi.nvim: gate.lua:1`](https://github.com/MizuchiLabs/tsugi.nvim/blob/d4b3ca5ab64f4d310857e4906c740b5dc78810b2/bench/gate.lua#L1)), capture tokens so that thresholds cost one run ([`halfword: evaluate_llm.py:57`](https://github.com/kolganovr/halfword/blob/2ce4289ac041c415fa6ead150dd0fb0e835d27ad/halfword/evaluate_llm.py#L57)), and score what matters ([`TabType: README.md:34`](https://github.com/nilava/TabType/blob/b75ea0e22bc565e57b133b2625a49d7e8a24c789/eval/README.md#L34)).

## Top mistakes, ranked

1. **Going quiet, or going wrong, under a Korean input method.** *CJK/IME.* We found no project that completes through a composing Hangul syllable. That's from searching source, not from a live Korean test. Ghostwriter turns automatic completions off under an input method, though forced requests bypass that ([`ghostwriter: CompletionCoordinator.swift:613`](https://github.com/mshll/ghostwriter/blob/53f2dc56ce193145d2b1cd13c5eb7f4914902a34/Ghostwriter/Coordinator/CompletionCoordinator.swift#L613)). GhostType turns auto-trigger off for any non-ASCII source ([`GhostType: CompletionController.swift:136`](https://github.com/mk668a/GhostType/blob/af6cff8751dc020ac3a2ff93f220e887a6e1b787/GhostType/Core/CompletionController.swift#L136)). ztype's language detection reads Hangul as English and asks for an English continuation ([`ztype: CompletionContext.swift:50`](https://github.com/xiaohei210509/ztype/blob/d90fd366b1aab7686f3f3c8038d1a85d98890f79/Sources/ztypeCore/CompletionContext.swift#L50)). LocalKey and FUTO predict from a composing buffer, but ASCII only.
2. **No confidence gate.** *Post-processing.* Every wrong guess gets shown, with the logits already in hand. [`cotabby: LlamaRuntimeModels.swift:198`](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Models/Runtime/LlamaRuntimeModels.swift#L198), [`twinny: provider.ts:507`](https://github.com/twinnydotdev/twinny/blob/9c03b58300a6abc75bd44207dae9687c92cc3b6f/src/extension/completion/provider.ts#L507).
3. **Scoring the whole suggestion, or inventing a score.** *Post-processing.* An average hides an unsure first word, the one a person judges. [`typer: llama_server.cpp:335`](https://github.com/whoisjson0/typer/blob/f6db9b4e1b33a2df820645f0d87fe273a54096ee/scripts/llama_server.cpp#L335), [`casecomplete: main.rs:1418`](https://github.com/drknowhow/casecomplete/blob/0569a1c908d00b0348ad75b5369b45846c531c59/crates/cc-app/src/main.rs#L1418). Heuristic points replace probability in [`LocalTypist: SuggestionPipeline.swift:247`](https://github.com/Joaov41/LocalTypist/blob/01ceed5e0d2a620b03aa680eed025379bc5b3ea0/Sources/LocalTypistCore/SuggestionPipeline.swift#L247).
4. **Volatile text before stable text, or a head that slides per key.** *Inference.* A long field then re-evaluates its body on every key, from the first token that differs. [`AutoComp: PromptBuilder.swift:101`](https://github.com/ThalesMMS/AutoComp/blob/a425cca162c745fff2ca5d582ae9f1261549d83f/Sources/AutoCompCore/Services/PromptBuilder.swift#L101), [`ztype: InferenceClient.swift:69`](https://github.com/xiaohei210509/ztype/blob/d90fd366b1aab7686f3f3c8038d1a85d98890f79/Sources/ztypeCore/InferenceClient.swift#L69), [`ibus-llm-assist: llm.py:100`](https://github.com/maximeallanic/ibus-llm-assist/blob/82178063c16ef94ff07bd1a946a5b1db23453e05/llm_assist/llm.py#L100).
5. **Throwing away the cache.** *Inference.* On every request ([`LocalTypist: CLlamaBridge.c:269`](https://github.com/Joaov41/LocalTypist/blob/01ceed5e0d2a620b03aa680eed025379bc5b3ea0/Sources/CLlamaBridge/CLlamaBridge.c#L269), [`Inkling-macOS: GatedDecoder.swift:98`](https://github.com/dafuct/Inkling-macOS/blob/5f5763e703967b169c17aaac0cef0767c4c866da/Sources/InklingMLX/GatedDecoder.swift#L98)) or on every cancel, the common case when typing fast ([`cotabby: LlamaRuntimeCore.swift:622`](https://github.com/FuJacob/cotabby/blob/8cdbea2d2619b0f89a73d46eb0bb856504d07343/Cotabby/Services/Runtime/Llama/LlamaRuntimeCore.swift#L622)).
6. **A chat template for continuation, then cleaning up the damage.** *Prompt.* A list of preambles to strip is the symptom ([`open_auto_complete: ModelRunner.swift:134`](https://github.com/GandalftheGUI/open_auto_complete/blob/1ca44d90440ca5d9236bf80f6f13fcbc603733e6/Sources/OpenAutoComplete/ModelRunner.swift#L134)). Trimming the model's leading space then glues words together ([`Opentypist: MLXProvider.swift:229`](https://github.com/tahashafiei/Opentypist/blob/fe6dcb1df59884324b9d976743ec1d6a1766e2ae/Opentypist/Opentypist/MLXProvider.swift#L229)).
7. **Decoding tokens one at a time into strings.** *CJK/IME.* It splits multibyte characters. [`Souffleuse: BeamGhostEngine.swift:651`](https://github.com/menufactory43/Souffleuse/blob/7b06e0b4fe319de89b5de843ef9e7a6b6190169a/Souffleuse/Sources/SouffleuseLlama/BeamGhostEngine.swift#L651). An ASCII-only grammar has the same effect on Korean, even in an otherwise elegant idea ([`ABC-Plus: TextLogic.swift:39`](https://github.com/lyx-27/ABC-Plus/blob/a3044b18cdaed96a44126cfd318b8047570a79ca/Sources/TextLogic.swift#L39)).
8. **Sampling and repetition penalties on a single ghost.** *Inference.* Identical keys give different ghosts, and the penalty hits the names and words most likely to repeat. [`Sombra: sombra_llama.c:53`](https://github.com/andlsac/Sombra/blob/97c19c0cdb04209358f5cc36e692f6bce0fe827a/Sources/CLlama/sombra_llama.c#L53), [`dopishi: SuggestionEngine.swift:47`](https://github.com/Fedotoff-Alex/dopishi/blob/d5736d790aa535ef1fd56a434d9316849dc14cec/Sources/DopishiLLM/SuggestionEngine.swift#L47).
9. **Debounce as the speed control.** *Lifecycle.* 650 ms is felt as lag ([`pluma: CompletionSuggestion.swift:21`](https://github.com/SLatz18/pluma/blob/72b15dba97f99764a921c1d5c3585c45f7becb66/Pluma/Autocomplete/CompletionSuggestion.swift#L21)). Cancelling between decode steps removes most of the need for it.
10. **Overlap trimming that deletes real letters.** *Post-processing.* Without a word-boundary check, `car` + `carpet` gives `pet` ([`twinny: formatter.ts:123`](https://github.com/twinnydotdev/twinny/blob/9c03b58300a6abc75bd44207dae9687c92cc3b6f/src/extension/completion/formatter.ts#L123)). See also [`obsidian-copilot-auto-completion: remove_overlap.ts:14`](https://github.com/j0rd1smit/obsidian-copilot-auto-completion/blob/9c112ce5a0a663b9983d561eb2830cd21c04e75c/src/prediction_services/post_processors/remove_overlap.ts#L14).
11. **Choosing behaviour from the model's file name.** *Prompt.* It breaks on a renamed file, and every new model needs a patch. [`dopishi: PromptBuilder.swift:95`](https://github.com/Fedotoff-Alex/dopishi/blob/d5736d790aa535ef1fd56a434d9316849dc14cec/Sources/DopishiCore/PromptBuilder.swift#L95), [`ollafim: ollafim.py:107`](https://github.com/Obrais-cloud/ollafim/blob/4c347e8a2d15b4026d71b4c340c002566fba64f1/ollafim.py#L107).
12. **Accepting by the clipboard, or claiming what can't be known.** *Accept.* A paste strategy overwrites what the user copied ([`KeyType: TextInsertion.swift:46`](https://github.com/johnbean393/KeyType/blob/21df2cc1f5271d3712d567e3c2491ac09174caf3/Packages/TextInsertion/Sources/TextInsertion/TextInsertion.swift#L46)). A successful write to an attribute doesn't mean the app drew it, so Tab may be taken for something invisible ([`text-predictor: GhostText.swift:95`](https://github.com/griffinwork40/text-predictor/blob/3166f4a8892a3f754c0d250b933ac2950bff729e/Sources/TextPredictor/GhostText.swift#L95)).
13. **Measuring the wrong latency.** *Tests.* Repeating one prefix and dropping the count of prompt tokens hides a cache miss ([`autocomplete: harness.py:26`](https://github.com/rrong12/autocomplete/blob/4dc7895934a6cb79b5f2b4ab2692030a86faec0f/harness.py#L26)). Only a replay of real typing catches this.

## What didn't count as evidence

OpenCotypist's inference is simulated ([`OpenCotypist: ModelLoader.swift:60`](https://github.com/criticalinsight/OpenCotypist/blob/1cc32da1fd49df70e698f084e6f1483a9e90e4be/src/Inference/ModelLoader.swift#L60)). LuminaText's MLX backend is a stub. GhostComplete defaults to cloud models. t-rhex/ghostwriter is a rewriter, not a completer. Souffleuse and cocotypist-llama are one app in two snapshots.

## All 66, with the licence as we found it

"Idea only" applies to anything AGPL, GPL, source-first or with no licence: Halftype copied no code from these, and no code from the others either. Checked with `gh repo view` and each repo's licence file on 2026-11-07.

| Project | Licence |
|---|---|
| [andlsac/Sombra](https://github.com/andlsac/Sombra) | MIT |
| [arewecoding/on-device-autocomplete-research](https://github.com/arewecoding/on-device-autocomplete-research) | None found, idea only |
| [ariobarin/Fillit](https://github.com/ariobarin/Fillit) | MIT |
| [BlinkResearchLabs/blink-edit.nvim](https://github.com/BlinkResearchLabs/blink-edit.nvim) | MIT |
| [BraedynL0530/WinCotypist](https://github.com/BraedynL0530/WinCotypist) | None found, idea only |
| [BrodySalvucci/Typist](https://github.com/BrodySalvucci/Typist) | MIT |
| [continuedev/continue](https://github.com/continuedev/continue) | Apache-2.0 |
| [criticalinsight/OpenCotypist](https://github.com/criticalinsight/OpenCotypist) | None found, idea only |
| [dafuct/Inkling-macOS](https://github.com/dafuct/Inkling-macOS) | MIT |
| [DaraSingh1998/foretype](https://github.com/DaraSingh1998/foretype) | MIT or Apache-2.0 |
| [dario-valles/shadowtype](https://github.com/dario-valles/shadowtype) | MIT |
| [drknowhow/casecomplete](https://github.com/drknowhow/casecomplete) | MIT |
| [Fedotoff-Alex/dopishi](https://github.com/Fedotoff-Alex/dopishi) | MIT |
| [feroult/zsh-localghost](https://github.com/feroult/zsh-localghost) | None found, idea only |
| [FuJacob/cotabby](https://github.com/FuJacob/cotabby) | AGPL-3.0, idea only |
| [FuJacob/cotabbyinference](https://github.com/FuJacob/cotabbyinference) | MIT |
| [futo-org/android-keyboard](https://github.com/futo-org/android-keyboard) | FUTO Source First 1.1-kb, idea only |
| [GandalftheGUI/open_auto_complete](https://github.com/GandalftheGUI/open_auto_complete) | MIT per README, no licence file |
| [ggml-org/llama.vim](https://github.com/ggml-org/llama.vim) | MIT |
| [ggml-org/llama.vscode](https://github.com/ggml-org/llama.vscode) | MIT |
| [griffinwork40/termauto](https://github.com/griffinwork40/termauto) | MIT |
| [griffinwork40/text-predictor](https://github.com/griffinwork40/text-predictor) | MIT |
| [IbrahimAlmansour-95/qalam-ai](https://github.com/IbrahimAlmansour-95/qalam-ai) | MIT |
| [IsraPerez98/TypeAlike](https://github.com/IsraPerez98/TypeAlike) | GPL-3.0, idea only |
| [j0rd1smit/obsidian-copilot-auto-completion](https://github.com/j0rd1smit/obsidian-copilot-auto-completion) | MIT |
| [jandiradmin/ExoKey](https://github.com/jandiradmin/ExoKey) | MIT |
| [Joaov41/LocalTypist](https://github.com/Joaov41/LocalTypist) | None found, idea only |
| [johannes-kaindl/ghostline](https://github.com/johannes-kaindl/ghostline) | AGPL-3.0, idea only |
| [johnbean393/KeyType](https://github.com/johnbean393/KeyType) | MIT |
| [khimaros/mortar](https://github.com/khimaros/mortar) | GPL-3.0, idea only |
| [kolganovr/halfword](https://github.com/kolganovr/halfword) | MIT |
| [lyx-27/ABC-Plus](https://github.com/lyx-27/ABC-Plus) | MIT |
| [marimo-team/codemirror-ai](https://github.com/marimo-team/codemirror-ai) | Apache-2.0 |
| [maximeallanic/ibus-llm-assist](https://github.com/maximeallanic/ibus-llm-assist) | MIT |
| [meffysto/cocotypist-llama](https://github.com/meffysto/cocotypist-llama) | None found, idea only |
| [mekanismvibe/opentypist](https://github.com/mekanismvibe/opentypist) | MIT |
| [menufactory43/Souffleuse](https://github.com/menufactory43/Souffleuse) | None found, idea only |
| [milanglacier/minuet-ai.nvim](https://github.com/milanglacier/minuet-ai.nvim) | GPL-3.0, idea only |
| [MizuchiLabs/tsugi.nvim](https://github.com/MizuchiLabs/tsugi.nvim) | Apache-2.0 |
| [mk668a/GhostType](https://github.com/mk668a/GhostType) | MIT |
| [Msde-7/cotabby-windows](https://github.com/Msde-7/cotabby-windows) | AGPL-3.0, idea only |
| [mshll/ghostwriter](https://github.com/mshll/ghostwriter) | GPL-3.0, idea only |
| [my7bropx/SmartType](https://github.com/my7bropx/SmartType) | MIT |
| [nikiomori/Pretype](https://github.com/nikiomori/Pretype) | MIT |
| [nilava/TabType](https://github.com/nilava/TabType) | MIT |
| [NinjaCatP/LocalKey-AI](https://github.com/NinjaCatP/LocalKey-AI) | MIT |
| [Obrais-cloud/ollafim](https://github.com/Obrais-cloud/ollafim) | MIT per README, no licence file |
| [OctavianTocan/ghostcomplete](https://github.com/OctavianTocan/ghostcomplete) | None found, idea only |
| [r3dbars/tilde](https://github.com/r3dbars/tilde) | MIT |
| [redclayai/glide](https://github.com/redclayai/glide) | MIT |
| [rrong12/autocomplete](https://github.com/rrong12/autocomplete) | None found, idea only |
| [shaunakg/obsidian-smart-compose](https://github.com/shaunakg/obsidian-smart-compose) | MIT per package.json, no licence file |
| [SLatz18/pluma](https://github.com/SLatz18/pluma) | MIT |
| [slyboyshish/YeType](https://github.com/slyboyshish/YeType) | AGPL-3.0, idea only |
| [stevyhacker/LokalBot](https://github.com/stevyhacker/LokalBot) | GPL-3.0, idea only |
| [Studentul404/LuminaText](https://github.com/Studentul404/LuminaText) | MIT |
| [t-rhex/ghostwriter](https://github.com/t-rhex/ghostwriter) | MIT |
| [TabbyML/tabby](https://github.com/TabbyML/tabby) | Apache-2.0 outside `ee/` |
| [tahashafiei/Opentypist](https://github.com/tahashafiei/Opentypist) | MIT |
| [ThalesMMS/AutoComp](https://github.com/ThalesMMS/AutoComp) | Apache-2.0 |
| [ThanabordeeN/ibus-llm-suggest](https://github.com/ThanabordeeN/ibus-llm-suggest) | MIT per README, no licence file |
| [TheKerbecs/ghosttab](https://github.com/TheKerbecs/ghosttab) | None found, idea only |
| [tollefj/local-fim.nvim](https://github.com/tollefj/local-fim.nvim) | MIT |
| [twinnydotdev/twinny](https://github.com/twinnydotdev/twinny) | MIT |
| [whoisjson0/typer](https://github.com/whoisjson0/typer) | MIT |
| [xiaohei210509/ztype](https://github.com/xiaohei210509/ztype) | MIT |
