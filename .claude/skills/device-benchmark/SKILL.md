---
name: device-benchmark
description: Procedure for measuring on-device Foundation Models latency, token counts, heat and battery on a physical iPhone, and for turning the exported JSON or a run log into a budget and pacing decision. Use when asked to benchmark, profile, or size the simulation for a device.
---

# Benchmark the on-device model on a phone

Claude cannot drive a physical iPhone. The human runs the app; you prepare and analyze.
The simulator borrows the Mac's model (AFM 3 Core, 4K) and says nothing about phone behavior,
heat or battery; only the phone counts here.

## Conditions (measured, not assumed)

On an iPhone 17 Pro Max, a flat-out two-game-day run (3 agents, ~160 calls, ~10 min):

- Plugged in: phone hot, planHour mean 5.3 s, latency drift first→last third +41%.
- Unplugged, after cooling: phone warm, planHour mean 4.6 s, drift +28%.

Charging adds its own heat and the phone throttles on the sum, so every benchmark and every
run that will be quoted is done **unplugged, after the phone has cooled, in Airplane mode**,
and starting from **60–70% battery** (the gauge is unreliable above ~90%, so a drop measured
from 100% means nothing). If the human runs it plugged in anyway, say so next to every number.

The file and the run summary must carry the condition: `batteryState` and `batteryLevel` at
start and end, `thermalState` at start, end and peak. Numbers without those fields are not
comparable between runs.

## Prepare

1. Make sure `BenchmarkView` builds and that it writes `smallville.benchmark.json` with: model
   variant name, context size, iOS version, device model, the condition fields above, and
   per-call `{kind, inputTokens, outputTokens, wallSeconds, ok}` for at least 20 calls of each
   kind (`planHour`, `converse`).
2. The human builds to the phone from `App/Smallville.xcodeproj` (regenerate with
   `cd App && xcodegen generate`; signing comes from `App/Config/Local.xcconfig`). Not from the
   package: its `smallville-run` scheme cannot install on a device.
3. Tell the human exactly what to do, in this order: Airplane mode on → unplug → wait until the
   phone is cool to the touch → note battery % → Benchmark tab, confirm it says
   **AFM 3 Core Advanced · 8192** → Run → wait for "Done" → Share → AirDrop the JSON → note
   battery % → attach the JSON. For a full run instead of the benchmark: Town tab, brain
   "On-device model", Start; the Xcode console log (one line per call) is the data, saved as
   `runs/phone-<what>.log`.

## Analyze

From the JSON, or from a run log (`kind agent: in N out N S.Ss` per line), compute per kind:
p50 and p95 wall seconds, mean input and output tokens, failure rate, and **latency drift**
(mean of the first third of calls vs the last third; more than ~15% is throttling). Then:

- Calls per agent-day from a real run (≈27 on the phone) are the planning number, not the
  45-call ceiling. Game-day wall time ≈ `agents × calls-per-agent-day × p50(all kinds)`;
  report it for 3, 10 and 25 agents, flat-out and at the throttled latency.
- Playable pace is one game-hour per two real minutes; report the agent-count ceiling at that
  pace. At that pace the duty cycle is ~25%, which is also the heat fix, so do not propose a
  smaller town for heat reasons before pacing exists.
- If p50 > 5 s or any prompt > 3,000 tokens, propose where to cut (fewer retrieved memories,
  shorter schema descriptions, fewer conversation turns) before proposing a smaller town.
- If `variantName` is not Core Advanced, note that the device runs the 3B Core model with a
  4K window and recommend the agent-count ceiling for it.
- Battery: report the % drop per game-day only when the run started below ~90%.

Write the result to `docs/benchmarks/<device>-<date>.md` with the numbers, the condition
line (plugged/unplugged, thermal states, battery start/end) and the recommendation.
