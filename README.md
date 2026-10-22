# Smallville for iOS

A port of Stanford's [Generative Agents](https://github.com/joonspk-research/generative_agents) ("Smallville") to a native iOS 27 app that runs **entirely on-device** using Apple's Foundation Models framework. No server, no API keys, no network.

**Status:** scaffold. The simulation core, Foundation Models adapter and app shell are stubs with the architecture, tests and agent configuration in place. See `docs/SETUP-CHECKLIST.md` for how the project is being built.

## What it does (goal)

A small town of generative agents (memory stream → retrieve → reflect → plan → act) runs at "ant farm" pace on the phone. You plant thoughts in agents ("you want to throw a Valentine's party at Hobbs Cafe"), watch the information spread, and the app detects the emergent behavior (who heard, who planned to go, who showed up) and lets you browse and export the evidence.

This demos behavioral generativity. From the on-device model's own output in [`phone-2day-verbose.log`](phone-2day-verbose.log):

- Isabella invites Maria (call #33, [line 3645](phone-2day-verbose.log#L3645)):
  `{"to": "Maria Lopez", "topic": "Valentine's Day party at Hobbs Cafe", "kind": "invite", "from": "Isabella Rodriguez", "storylineID": "valentines-party"}`
- Maria invites Klaus (call #98, [line 10722](phone-2day-verbose.log#L10722)):
  `{"to": "Klaus Mueller", "topic": "Valentine’s Day party", "kind": "invite", "from": "Maria Lopez", "storylineID": "valentines-party"}`

In this run: Isabella was forbidden to talk to Klaus (Isabella ⟂ Klaus option is ON), and the goal was for Klaus to be invited to the party (via Maria, who was previously invited by Isabella). There is logic where one cannot invite another to a party unless they are Isabella or have been invited already, so even though Isabella couldn't talk to Klaus, Maria couldn't invite Klaus until she herself was invited. 

> **See it without building anything:** [`phone-2day-verbose.log`](phone-2day-verbose.log) is the raw output of this two-day run on an iPhone (Day 1 07:00 to Day 2 21:00, 144 model calls), with the full instructions, prompt, schema and response of every on-device model call. Search it for `"kind": "invite"` to find the invitations.

## Requirements

- Xcode 27 on an Apple silicon Mac running macOS 27 with Apple Intelligence enabled (needed to run the headless simulator on the Mac's model).
- A device that supports Apple Intelligence. iPhone 17 Pro, 17 Pro Max and iPhone Air get the larger on-device model (AFM 3 Core Advanced, 8K context); other devices get AFM 3 Core (4K) and should run fewer agents. The app reports which one it got.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to generate the Xcode project.

## Build and run

```bash
swift test                                   # core logic, no model needed
swift run smallville-run --minutes 60 --agents 3        # headless sim, stub brain
swift run smallville-run --minutes 60 --agents 3 --fm   # headless sim, Mac's on-device model
cd App && xcodegen generate && open Smallville.xcodeproj # generate xcodeproj for iOS builds
```

## Art assets

The original Smallville art is by three artists and is **not** redistributed here. `scripts/fetch-assets.sh` copies the map and sprite files from your own clone of the Stanford repository into `Assets/ThirdParty/` (gitignored). See `ATTRIBUTION.md`.

## License

Code: Apache-2.0 (see `LICENSE`, `NOTICE`). This project is derived from the Apache-2.0 licensed `generative_agents` repository; cite the paper if you use it in research.
