---
paths:
  - "Sources/SmallvilleFM/**"
  - "App/**"
---

# Rules for Foundation Models and app code

- `SystemLanguageModel` only. Creating a `PrivateCloudComputeLanguageModel` or any third-party `LanguageModel` is a bug, not an option.
- Every `respond` uses guided generation: `generating:` with a `@Generable` type, or `schema:` with a `DynamicGenerationSchema` whose output is decoded into a `@Generable` mirror. Free-text `respond(to:)` is not used anywhere.
- Each brain call starts a fresh `LanguageModelSession` whose instructions are the agent's fixed persona (ADR 13); everything that changes goes in the prompt, at the end. No `prewarm()`.
- Handle every error case explicitly: `LanguageModelError`, `SystemLanguageModel.Error`, `LanguageModelSession.Error` and `GeneratedContent.ParsingError` on 27, and `GenerationError` on 26. `guardrailViolation` and `refusal` map to `BrainError.refused`. A context overflow retries once with half the retrieved memories. Cancellation propagates.
- Prompts are built by `Prompts` and stay under 3,000 tokens. Prefer trimming retrieved memories over trimming the schema.
- Wrap all FoundationModels code in `#if canImport(FoundationModels)` so the package still builds on Linux CI.
- iOS 27-only API (`variant`, `usage`) goes behind `#available(iOS 27.0, macOS 27.0, *)` with an iOS 26 fallback. Anything you could not confirm with the `apple-docs` subagent gets a `// VERIFY:` comment.
- Never read or write files under `Assets/ThirdParty/` directly. Use `AssetCatalog` and treat a missing folder as a normal state, not an error.
