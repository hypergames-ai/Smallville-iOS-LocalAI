---
name: device-benchmark
description: Procedure for measuring on-device Foundation Models latency and token counts on a physical iPhone, and for turning the exported JSON into a budget decision. Use when asked to benchmark, profile, or size the simulation for a device.
---

# Benchmark the on-device model on a phone

Claude cannot drive a physical iPhone. The human runs the app; you prepare and analyze.

## Prepare

1. Make sure `BenchmarkView` builds and that it writes `smallville.benchmark.json` with: model variant name, context size, iOS version, device model, and per-call `{kind, inputTokens, outputTokens, wallSeconds, ok}` for at least 20 calls of each kind (`planHour`, `converse`).
2. Build to the device through Xcode (XcodeBuildMCP can build; installing on a physical device needs signing configured in `App/Config/Local.xcconfig`).
3. Tell the human exactly what to do: open Benchmark tab → Run → wait for "done" → tap Share → AirDrop or save the JSON → attach it in the conversation.

## Analyze

From the JSON compute, per kind: p50 and p95 wall seconds, mean input and output tokens, failure rate. Then:

- Game-day wall time ≈ `agents × 45 × p50(all kinds)`. Report it for 3, 10, and 25 agents.
- If p50 > 5 s or any prompt > 3,000 tokens, propose where to cut (fewer retrieved memories, shorter schema descriptions, fewer conversation turns) before proposing a smaller town.
- If `variantName` is not Core Advanced, note that the device runs the 3B Core model with a 4K window and recommend the agent-count ceiling for it.

Write the result to `docs/benchmarks/<device>-<date>.md` with the numbers and the recommendation.
