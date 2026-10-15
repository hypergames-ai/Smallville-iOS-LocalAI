---
name: run-sim
description: Run the headless Smallville simulation and read its budget and discovery output. Use when asked to "run the sim", check the call budget, or verify that a storyline propagates.
---

# Run the headless simulation

```bash
# Stub brain (deterministic, no model): the default for checking logic and budget.
swift run smallville-run --minutes 2880 --agents 3 --seed 42

# Mac's on-device model (macOS 27, Apple Intelligence on). Slow; use for quality checks only.
swift run smallville-run --minutes 240 --agents 3 --fm

# Save the report for comparison
swift run smallville-run --minutes 2880 --agents 3 --out runs/$(date +%Y%m%d-%H%M).json
```

`--minutes` is game-minutes (1440 = one game-day). `--no-party` skips the default Valentine's whisper. `--whisper "isabella: <text>"` adds a custom one.

## Reading the output

The run ends with one JSON object:

- `budget.meanCallsPerAgentDay` must stay ≤ 45 and `budget.largestPromptTokens` ≤ 3000; `budget.withinBudget` summarizes both.
- `budget.callsByKind` shows where calls go. `planHour` should dominate (~15/day). If `converse` or `reflect` climbs above ~5/day, gating is broken.
- `discoveries[]` has `knows`, `invited`, `accepted`, `attended`, and `diffusion` edges `(from, to, at)`. For the Valentine's test, `knows.count ≥ 2` and `attended` non-empty after two game-days is the acceptance bar.
- `brainFailures` counts calls that threw `BrainError`. A few refusals on `--fm` are normal; any on the stub brain is a bug.

Paste the JSON block verbatim into your report; don't paraphrase numbers.
