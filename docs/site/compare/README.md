# Halftype against the apps people use (2026-11-09)

The set: macOS's own inline predictions, Cotypist (closed, the best known), and the two biggest open Mac apps by GitHub stars in `local-autocomplete/census/uniq.tsv` (refreshed 2026-11-09): Cotabby (1,105, AGPL-3.0) and KeyType (578, MIT). TabType (55) and smaller were left out. Grammarly is cloud-based, so it gets a privacy comparison, not a resource one.

Every app runs with its default model on one M5 with 16 GB. Memory is `footprint` (phys_footprint).

| | Default model | Download | Memory 9 min after launch, no typing | CPU at rest | Model mapped at rest |
|---|---|---|---|---|---|
| Halftype 0.1.5 | Qwen 3.5 0.8B Q4_K_M | 0.53 GB | 79 MB (README, `e2e.sh --measure`, unloaded after 5 idle min) | 0.13-0.27% (README) | no |
| KeyType 1.8 | Qwen 3.5 2B Q4_K_M (`ModelContainer.defaultModelFilename`) | 1.27 GB | 37 MB, **but switched off**: no Accessibility, so it never started | 0.1%, switched off | no |
| Cotypist 2026.5.2 | Gemma 4 E2B Q4_C (as it downloaded it here) | 2.98 GB | 383 MB (478 MB in a first run) | 0.2%, 13% about every 5 min | yes |
| Cotabby 0.6.2-beta | Gemma 4 E2B Q6_K ("Everyday", first in `preferredModelNames`) | 3.85 GB | 185 MB | 2.2%, steady | yes |

- `idle.sh <app> <process name>` made the `*-idle.txt` files. It takes no keys or focus. Sizes are from the Hugging Face API.
- Cotabby and KeyType ran from their notarized release DMGs, out of a scratch folder, never installed in /Applications. Their models were placed where each app looks (`~/Library/Application Support/Cotabby/LlamaRuntime/`, `~/Library/Application Support/KeyType/Models/`). Neither went through its onboarding or got Accessibility.
- Halftype couldn't be re-measured by `idle.sh`: another session's dev build was running, and two copies fight over the key tap.
- Korean: macOS lists inline predictions for English, French and Spanish only (apple.com/macos/feature-availability). For Cotabby and KeyType, the source audit (`docs/audit.md`) found no completion through a composing syllable. That was from reading source, not a live test.
- **Trap: an app without Accessibility may not be running at all.** KeyType starts its completion engine only once Accessibility is granted (`AppDelegate.syncContextCaptureWithPermission`). It then loads the model at start and shuts it down only on a model switch or quit (`CompletionController.start`, `shutdown`). Its 37 MB is the app switched off, so the page leaves it out at rest. Before trusting any at-rest number, check that the model got mapped (`vmmap | grep gguf`) or read when the source loads it.
- Not measured yet: speed and accuracy while typing, and memory while typing. Each needs a typed replay that takes the keyboard.
