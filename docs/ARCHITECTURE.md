# Architecture

## One sentence

A pure-Swift simulation core (actors, value types, no model) asks a `Brain` for a small number of structured decisions per agent per game-hour, records everything it did in an event log, and a detector reads that log to find emergent social behavior.

## Targets

```
SmallvilleCore      Simulation, MemoryStream, retrieval, StorylineDetector, StubBrain   (Foundation only)
SmallvilleFM        FoundationModelsBrain: @Generable types, DynamicSchemas, Prompts (FoundationModels, NaturalLanguage)
smallville-run      Headless CLI: runs N game-days, prints budget + discoveries JSON
SmallvilleCoreTests Swift Testing, stub brain only
App/                SwiftUI shell: Town (SpriteKit), Discoveries (nav list), Benchmark
```

Dependency direction is strictly downward: App → FM → Core. The core never imports anything above it.

## The cognitive loop (per agent)

Smallville's loop is kept, its call structure is not.

| Stage | Original (reverie) | Here | Calls/agent-day |
| --- | --- | --- | --- |
| Identity revision | `revise_identity`: 3 calls at the start of each new day (plan note, thought note, `currently`) | 1 call at wake from day 2, before the day plan → `IdentityRevision`; replaces `currently` and stores the notes as a `.plan` memory; `currently` sits at the end of every prompt, not in the instructions (ADR 14) | 1 |
| Day plan | 1 call + hourly decomposition calls | 1 call at wake → `DayPlan` | 1 |
| Hour plan | ~8 calls per action (task decomposition, sector, arena, object, emoji, triple, state) | 1 call per waking hour → `HourPlan` with 1–3 `PlannedAction`s, each carrying location, emoji and event triple | ~15 |
| Perception | poignancy call per observation | observations appended with a default score; one batched `ratePoignancy` call every 4 waking hours | ~4 |
| Reaction gating | model decides whether to react | rules: co-located, awake, cooldown, per-day cap, not a `noContactPairs` pair | 0 |
| Conversation | 1 call per utterance | 1 call → whole `Conversation` (turns, `SocialAct`s, conveyed storylines, two summaries) | ≤4 |
| Reflection | several calls per trigger | 1 call when accumulated importance crosses a threshold, at most 3 per day and ≥1 h apart → `[Reflection]` | ~2, cap 3 |
| **Total** | 600–1,000 | | **~27, budget 45** |

The day- and hour-plan prompts name the profile's workplace, favorite spot and home, and tag them (plus storyline venues) in the location list, so the model plans the day where the profile implies; nothing in the core forces a location.

Every brain method returns `BrainResponse<T>` = value + `BrainCallReceipt` (tokens, wall time). On the device, each call is a fresh session with the agent's persona as instructions (the initiator's for a conversation; ADR 13); receipts carry the response's real `usage` on iOS 27 (26.4: `tokenCount`, unverified on a device; earlier: an estimate). Hour plans and conversations are generated against a `DynamicGenerationSchema` built per call, so locations, storyline ids and speaker names can only be known values, then decoded into the `@Generable` mirror types. `Simulation.record` feeds `CallBudget`; `budget.summary()` is the number the tests and the runner print. A conversation is one call in the totals and half a call on each participant's agent-day: the per-agent limit is a worst case, and either participant's device would run the same inference.

An agent's location list (`AgentContext.knownLocations`) runs workplace, favorite spot, known storyline venues, home, then public places, and that is also the hour-plan schema's choice order: daytime places first, so the list itself doesn't pull agents home. A storyline event has a start and a duration (`durationMinutes`, an hour if unset): its venue is listed and tagged "storyline venue" only until the event is over, and the prompts show the end time and mark a past event "(over)", so agents move on instead of staying at the venue.

## Memory

`MemoryStream` is an append-only array of `MemoryNode` (kind, text, poignancy 1–10, embedding, `Provenance`, `storylines`). Retrieval is the paper's score: normalized recency (exponential decay on last access) + importance + relevance (cosine), top-k, and it touches `lastAccessed`.

`Provenance` is the part the original didn't have and this project is built around:

- `.observed` — the agent saw it
- `.told(by:at:)` — another agent conveyed it in a conversation
- `.reflected(from:)` — synthesized from other nodes
- `.whispered` — the player planted it

A `Storyline` is a tagged seed (the Valentine's party). Conversation outputs list which storylines were conveyed; the receiver's chat memory gets `.told(by:)` and the storyline tag. "Who knows" is therefore a query, and "who told whom" is a graph.

Embeddings: `Embedder` protocol in the core; `HashingEmbedder` (bag of words, deterministic) for tests and Linux; `NLSentenceEmbedder` (NaturalLanguage) in the FM target for devices.

## Detection

`StorylineDetector.detect` is a pure function of (memories, events, positions):

- **knows** — agents with any memory tagged with the storyline
- **diffusion** — edges from `.told(by:at:)` provenance
- **invited / accepted** — `SocialAct`s in `.conversed` events with that storyline. The simulation keeps an invite only if the inviter was whispered the storyline or was invited to it earlier (hearing of it is not enough), and an accept only if it answers such an agent. A kept accept from someone not yet invited, with no invite before it, gets an invite inserted ahead of it: the model often files "would you help with the party?" as `plan`.
- **attended** — agents with at least `minimumDwellSamples` (default 2, i.e. 20 min) `PositionSample`s at the storyline's `targetLocation` within ±60 min of `eventTime`. The host is included, not excluded; `Discovery.host` names them so the UI can label them.
- **diffusion** edges are deduplicated to the earliest told-by time per (teller, listener) pair.

A later "chronicler" pass (one call per game-hour over the compressed social-act log) will find unseeded headlines; it is deliberately not in the skeleton.

## Time

`SimTime` is minutes since start. One tick is 10 minutes. The sim starts Day 1 07:00. Hour boundaries trigger planning; day boundaries reset per-day counters. Agents sleep outside `[wakeHour, 22)` and make no calls while asleep.

## Determinism

Same (seed, whispers, brain) → identical `events`. Dictionaries are iterated through sorted keys or the `order` array. Ids are counters. The only RNG is `SeededRandom`. The FM brain is not deterministic (the model isn't), so determinism tests use the stub.

## Budgets

- ≤ 3,000 tokens per prompt, counted as instructions + prompt + schema + response (`CallBudget` adds a receipt's input and output tokens; `largestPromptTokensByKind` shows which call kind is closest)
- ≤ 45 calls per agent per game-day, mean over the run
- `CallBudget` counts prompts over 3,000 as `overBudgetPrompts`; `withinBudget` is false if any exist or if any agent-day exceeds 45

## The app

`SimulationController` (`@MainActor @Observable`) owns a `Simulation` and advances it one game-hour at a time in a `Task`, no faster than `secondsPerGameHour` (default 0.25 s, the flat-out floor, so quiet night hours can't publish several snapshots in one frame), publishing `Snapshot`s and `Discovery`s. The Town scene renders from snapshots only. The Discoveries list is a `NavigationStack` over `Discovery` with evidence drill-down; attendance is shown with the host separated, as in "3 attended (host + 2)", using `Discovery.host` (view change planned for Phase 6). The Benchmark view exists so a human with a phone can produce numbers the agent can reason about.

## What is deliberately not here yet

Tiled map loading and pathfinding (positions are location ids, not tiles); a real "chronicler" detector; export/report bundles; adapters or evals. Each is a planned task in `docs/SETUP-CHECKLIST.md`.
