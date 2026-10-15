---
paths:
  - "Sources/SmallvilleCore/**"
---

# Rules for the simulation core

- The only `import` allowed in this target is `Foundation`. No FoundationModels, NaturalLanguage, SwiftUI, SpriteKit, UIKit, Combine, or os.log-specific types in signatures.
- The core never talks to a model directly. It calls `any AgentBrain` and gets back plain `Codable` value types. `@Generable` types live in `SmallvilleFM`, not here.
- Every brain call goes through `Simulation.record(_:_:_:)` so `CallBudget` sees it. Adding a new kind of call means adding a `BrainCallKind` case and a line in `docs/ARCHITECTURE.md` explaining why the budget can afford it.
- Reaction gating (should two agents talk?) is rules, not a model call. Keep it that way.
- Iterate dictionaries in a deterministic order (sort the keys, or use the `order` array). Two runs with the same seed and whispers must produce identical `events`.
- No `print`, no `Date()`, no `UUID()`: time comes from `SimTime`, ids from counters, randomness from `SeededRandom`.
