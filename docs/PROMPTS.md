# Driving the agent: prompts by phase

These are starting points, not scripts. Each one states an outcome and an acceptance test; the agent decides the steps. Edit them as you learn what this agent needs to hear.

Format: **Prompt** (what to type) → **What good looks like** → **If it goes sideways**.

---

## Prompt 1 — Make the scaffold compile (Phase 2)

Model: Opus 5.5, effort medium. Fresh session.

```
The Swift in this repo was written without a compiler. Make `swift build` and `swift test` pass without changing the architecture, the public API shapes, or anything in CLAUDE.md or .claude/rules.

Rules for this task:
- Run `swift build` first and work from the compiler's errors; don't rewrite files speculatively.
- Every line marked `// VERIFY:` is an API detail I wasn't sure of. Check each one with the apple-docs subagent before changing it, and remove the marker once confirmed.
- If a test is failing because the stub simulation's behavior doesn't match the test's expectation, tell me which one and why before changing either; don't weaken assertions.
- Finish by running `swift run smallville-run --minutes 2880 --agents 3` and paste the final JSON block.
```

**Good:** builds first, fixes in small batches, one subagent call per VERIFY marker, ends with test output and the JSON block. Total diff is mostly small signature fixes.

**Sideways:** it starts restructuring files or "simplifying" the actor. `Esc`, then: "Stop. Revert the restructuring. Fix only compile errors, smallest change per error." If it edits a rule file, that's the moment to say: "Rules are not yours to change. Propose the change in your report instead."

---

## Prompt 2 — Plan the core (Phase 3)

Model: Fable 5.1. Plan mode (Shift+Tab).

```
Read docs/ARCHITECTURE.md and docs/DECISIONS.md, then the current Sources/SmallvilleCore. Plan the work to take the core from skeleton to the design in ARCHITECTURE.md, in this order of value: (1) the hourly planner with proper action decomposition and location choice constrained to known locations, (2) perception and memory with the recency/importance/relevance retrieval from the paper, (3) conversation gating and summaries with provenance, (4) reflection triggers, (5) the storyline detector with attendance from the position log.

For each step give: the files touched, the brain calls it adds or removes and the resulting calls-per-agent-day estimate, and the test that proves it. Flag anything that could push a prompt past 3,000 tokens. Keep the stub brain able to drive every step so tests never need the model.
```

**Good:** a plan with per-step call accounting and named tests; it asks you one or two real questions (e.g., whether reflections should be able to spawn new storylines).

**Sideways:** the plan adds model calls to decide things rules can decide (should they talk? is this location valid?). Reply: "Steps 1 and 3 add calls. Replace those with rules in the core and re-estimate."

---

## Prompt 3 — Implement the core and runner (Phase 4)

Model: Fable 5.1, effort high. Same session as the plan, after approving it. Set a goal first:

```
/goal swift test passes, and `swift run smallville-run --minutes 2880 --agents 3` prints withinBudget=true with knows.count >= 3 and attended.count >= 2 for the Valentine's storyline
```

Then:

```
Implement the approved plan. Work step by step; after each step run the test-runner subagent and keep going only when it's green. Keep the stub brain deterministic. When all five steps are done, run the sim-reviewer subagent, address its findings, and give me a report: what changed per step, the final budget JSON, and anything you'd want a human to decide.
```

**Good:** a long autonomous run with periodic green checkpoints; the report lists decisions it made and open questions.

**Sideways:** it burns an hour on one step. Check in: "Status? What's blocking?" If it's a design ambiguity, decide it. If it's fighting the type checker, "Write the smallest version that compiles and leave a TODO."

---

## Prompt 4 — Adversarial review before commit (any phase)

```
Run the sim-reviewer subagent on the current diff. Then fix every finding it rates as a rule violation, and for the rest tell me which you'd fix and which you'd push back on, and why.
```

**Good:** it argues with the reviewer where the reviewer is wrong. That disagreement is where you learn what the code actually does.

---

## Prompt 5 — Foundation Models adapter (Phase 5)

Model: Opus 5.5, effort high.

```
Make Sources/SmallvilleFM a real adapter. For each AgentBrain method, build the prompt with Prompts, respond with the matching @Generable type, and map into the core types. Verify every FoundationModels signature with the apple-docs subagent (iOS 26 vs 27 differences matter: usage, variant). Constrain location and storyline choices to known values using DynamicGenerationSchema rather than free strings. Record real token counts in BrainCallReceipt.

Acceptance: `swift run smallville-run --minutes 240 --agents 3 --fm` completes on this Mac with withinBudget=true and brainFailures <= 3. Paste the JSON and three example conversations verbatim.
```

**Good:** it probes the model's availability first and tells you the variant and context size it got on your Mac; it reports failures by error case.

**Sideways:** prompts over 3,000 tokens. "Which part of the prompt is largest? Cut retrieved memories to 5 and shorten @Guide descriptions before anything else."

---

## Prompt 6 — First eval (Phase 5)

```
Using Apple's Evaluations framework, add an eval target that runs the Valentine's scenario on the on-device model for one game-day and scores: did at least one agent other than Isabella learn about the party, and did any conversation contain an invite act? Check the framework's API with apple-docs first. Wire it so `swift test` still never calls the model; the eval runs only when explicitly invoked.
```

---

## Prompt 7 — App shell (Phase 6)

Model: `opusplan` in the CLI with XcodeBuildMCP, or Xcode's agent.

```
Start in plan mode. Make the iOS app build and run on the iPhone 17 Pro simulator. Keep App/project.yml as the source of truth (regenerate with xcodegen; never edit the .xcodeproj). Wire SimulationController to run the stub brain by default with a toggle for the on-device model. The Discoveries tab must show the Valentine's discovery after one game-day of stub simulation, with drill-down to the evidence memories. Build and launch through XcodeBuildMCP and send me a screenshot of the Discoveries tab.
```

---

## Prompt 8 — Benchmark view (Phase 6)

```
Finish BenchmarkView per the device-benchmark skill: probe the model, run 20 planHour and 20 converse calls on a fixed sample context, record per-call wall time and token counts, write smallville.benchmark.json, and offer it through ShareLink. Verify on the simulator that the file is written even when the model is unavailable (it should record the unavailable reason and zero calls).
```

---

## Prompt 9 — Analyze the phone numbers (Phase 7)

Attach the JSON from the phone, then:

```
Use the device-benchmark skill on the attached benchmark JSON. Give me the agent-count ceiling for this device at 1 game-hour per 2 real minutes, and the single biggest prompt cut that would raise it.
```

---

## Things to say that work

- "Show me the plan before editing." (anything multi-file)
- "What's the test that proves this?" (anything you can't see)
- "Smallest change per error." (compile fixes)
- "Which part is largest?" (budget problems)
- "Status? What's blocking?" (long silences)
- "Revert that and tell me why you did it." (surprises)
- "Put that in CLAUDE.md as a rule, phrased as a constraint, under Conventions." (a correction you've made twice)
