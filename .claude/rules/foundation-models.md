---
paths:
  - "Sources/SmallvilleFM/**"
  - "App/**"
---

# Rules for Foundation Models and app code

- `SystemLanguageModel` only. Creating a `PrivateCloudComputeLanguageModel` or any third-party `LanguageModel` is a bug, not an option.
- Every `respond` call uses `generating:` with a `@Generable` type. Free-text `respond(to:)` is not used anywhere.
- One `LanguageModelSession` per agent, created lazily, instructions fixed for the life of the session (the persona goes in instructions; everything that changes goes in the prompt, at the end). Call `prewarm()` when the session is created.
- Handle every `LanguageModelSession.GenerationError` case explicitly. `guardrailViolation` and `refusal` map to `BrainError.refused` so the simulation skips that one reaction; `exceededContextWindowSize` resets the session and retries once.
- Prompts are built by `Prompts` and stay under 3,000 tokens. Prefer trimming retrieved memories over trimming the schema.
- Wrap all FoundationModels code in `#if canImport(FoundationModels)` so the package still builds on Linux CI.
- iOS 27-only API (`variant`, `usage`) goes behind `#available(iOS 27.0, macOS 27.0, *)` with an iOS 26 fallback. Anything you could not confirm with the `apple-docs` subagent gets a `// VERIFY:` comment.
- Never read or write files under `Assets/ThirdParty/` directly. Use `AssetCatalog` and treat a missing folder as a normal state, not an error.
