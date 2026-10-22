# Smallville for iOS

A port of Stanford's [Generative Agents](https://github.com/joonspk-research/generative_agents) ("Smallville") to a native iOS 27 app that runs **entirely on-device** using Apple's Foundation Models framework. No server, no API keys, no network.

**Status:** scaffold. The simulation core, Foundation Models adapter and app shell are stubs with the architecture, tests and agent configuration in place. See `docs/SETUP-CHECKLIST.md` for how the project is being built.

## What it does (goal)

A small town of generative agents (memory stream → retrieve → reflect → plan → act) runs at "ant farm" pace on the phone. You plant thoughts in agents ("you want to throw a Valentine's party at Hobbs Cafe"), watch the information spread, and the app detects the emergent behavior (who heard, who planned to go, who showed up) and lets you browse and export the evidence.

This demos behavioral generativity:
"Isabella Rodriguez invited Maria Lopez to Valentine's Day party at Hobbs Cafe"
"Maria Lopez invited Klaus Mueller to Valentine's Day party at Hobbs Cafe"
In this run: Isabella was forbidden to talk to Klaus (Isabella ⟂ Klaus option is ON), and the goal was for Klaus to be invited to the party (via Maria, who was previously invited by Isabella). There is logic where one cannot invite another to a party unless they are Isabella or have been invited already, so even though Isabella couldn't talk to Klaus, Maria couldn't invite Klaus until she herself was invited. 

## Requirements

- Xcode 27 on an Apple silicon Mac running macOS 27 with Apple Intelligence enabled (needed to run the headless simulator on the Mac's model).
- A device that supports Apple Intelligence. iPhone 17 Pro, 17 Pro Max and iPhone Air get the larger on-device model (AFM 3 Core Advanced, 8K context); other devices get AFM 3 Core (4K) and should run fewer agents. The app reports which one it got.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to generate the Xcode project.

## Build and run

```bash
swift test                                   # core logic, no model needed
swift run smallville-run --minutes 60 --agents 3        # headless sim, stub brain
swift run smallville-run --minutes 60 --agents 3 --fm   # headless sim, Mac's on-device model
cd App && xcodegen generate && open Smallville.xcodeproj
```

## Art assets

The original Smallville art is by three artists and is **not** redistributed here. `scripts/fetch-assets.sh` copies the map and sprite files from your own clone of the Stanford repository into `Assets/ThirdParty/` (gitignored). See `ATTRIBUTION.md`.

## License

Code: Apache-2.0 (see `LICENSE`, `NOTICE`). This project is derived from the Apache-2.0 licensed `generative_agents` repository; cite the paper if you use it in research.
