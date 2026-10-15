# Decisions

Short ADRs. Newest at the bottom. Change a decision by adding a new entry, not by editing an old one.

## 1. Offline only, Foundation Models only

No network, no Private Cloud Compute, no third-party providers. PCC's per-user daily quota is the wrong shape for a simulation that makes hundreds of calls a day, its entitlement is per developer account (so people building from source wouldn't have it), and "entirely on the phone" is the interesting constraint. Third-party models would reintroduce an API key for every user of a GitHub project.

## 2. Keep the cognitive loop, discard the call structure

The paper's memory → retrieve → reflect → plan → act architecture is the thing being ported. Reverie's 600–1,000 calls per agent-day existed because GPT-3.5 made it cheap; on a phone every call is 2–5 s, so decomposition moves into single guided-generation calls that return whole structures.

## 3. Core is pure Swift; `@Generable` lives in the adapter

The core builds on Linux and tests without a model. `@Generable` requires FoundationModels, so the adapter defines mirror types and maps to plain `Codable` core types. The cost is one mapping layer; the benefit is that every test and the CI run are model-free and deterministic.

## 4. Reaction gating is rules, not a model call

Whether two co-located agents talk is decided by cooldowns and per-day caps. A model call here would be the single largest budget leak (it runs every tick for every pair).

## 5. Budgets are hard constraints in CLAUDE.md

3,000 tokens per prompt (the Core model's window is 4K; Core Advanced's is 8K; prompts must fit the smaller) and 45 calls per agent-day (keeps a 10-agent day under ~35 minutes at ~3.5 s/call). They are written as rules so the agent raises its hand before growing them rather than silently drifting.

## 6. Provenance on every memory

Added so emergent behavior can be *detected* rather than inferred by reading transcripts, which is how the paper did it. `.told(by:at:)` turns information diffusion into a graph query.

## 7. One session per agent, fixed instructions

Persona in `Instructions` (cached prefix), everything variable at the end of the prompt. Sessions are reset on context overflow. With 10+ sessions interleaving, cache hits aren't guaranteed, so prompts stay short regardless.

## 8. Stub brain is a first-class component

`StubBrain` is deterministic and knows just enough to propagate a storyline, so the runner, the detector and the UI can be developed and tested end to end without the model. It is not a simulation of the model's quality.

## 9. XcodeGen for the app project

`project.yml` is diffable and the agent can edit it; `.xcodeproj` is neither. The generated project is gitignored.

## 10. Third-party art is fetched, never committed

The Stanford repo's code is Apache-2.0 but its art is by three artists under their own terms (LimeZu's free tier is non-commercial and non-redistributable; pipoya forbids redistribution as an asset). `scripts/fetch-assets.sh` copies from the user's own clone into a gitignored folder; `AssetCatalog` treats absence as normal. Fallback plan if permission is refused: re-skin with CC0/LPC assets.

## 11. No package dependencies in the skeleton

Argument parsing in the runner is hand-rolled rather than pulling swift-argument-parser, to keep "ask before adding a dependency" honest from day one. Revisit when the CLI grows.

## 12. Idle-game pacing is the product

At ~45 calls per agent-day and 2–5 s per call, a 10-agent town is ~30 minutes of inference per game-day. The app is designed as an ant farm you check on, not a real-time game, and the sim runs only in the foreground (background inference is rate-limited by the OS).

## 13. One fresh session per model call (supersedes the session clause of 7)

Measured on macOS 27 (AFM 3 Core, 4,096-token context): a reused `LanguageModelSession` resends its whole transcript, so the same short prompt cost 161, 279, then 395 input tokens over three calls, while a fresh session stayed at 151; `cachedTokenCount` was 0 in every case. With real prompts of 1,000–1,500 tokens, a long-lived per-agent session crosses the 3,000-token budget by its second or third call, and the history it carries is what the memory stream already supplies. So every brain call starts a new session whose instructions are the agent's fixed persona, and the per-call cost is just instructions + prompt + schema + response. `prewarm` is not used (Apple advises it only with a second or more of lead time). A context overflow is retried once with half the retrieved memories; a second overflow is a `BrainError.malformed` and the simulation skips that decision. Revisit if a later OS reports cached prefix tokens across sessions.
