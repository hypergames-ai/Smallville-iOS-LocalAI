# Setup checklist

Phases 0–1 are you at the keyboard. From phase 2 on, the pattern is always the same: you set the **context** (CLAUDE.md, rules, skills), the **verification** (tests, the runner, hooks), the **scope** (plan mode, one task per session), and the **model/effort**; the agent does the typing. Each phase names the lever it teaches. `docs/PROMPTS.md` has the exact prompts.

## Phase 0 — Machine (you, ~30 min)

- [ ] Xcode 27 installed, `xcode-select -p` points at it, iOS 27 platform downloaded. `swift --version` works in Terminal.
- [ ] macOS 27 with Apple Intelligence turned on (System Settings → Apple Intelligence & Siri). The headless `--fm` run needs it.
- [ ] `brew install xcodegen`
- [ ] Claude Code current: `claude update`, then `claude` → `/login`. Run `/model` and confirm Opus 5.5 is the default and Fable 5.1 is in the picker.
- [ ] Claude Code Desktop installed (optional, nicer diff review). Note its simulator pane needs Xcode 26.x selected; with Xcode 27 you use XcodeBuildMCP or Xcode's own agent instead.
- [ ] Xcode agent: Xcode → Settings → Intelligence → Anthropic → sign in. It reads the repo's `CLAUDE.md` like the CLI does. Its own config dir is `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/`.
- [ ] Node present (`node --version`) so `npx xcodebuildmcp` can run.

## Phase 1 — Repo (you, ~15 min)

- [ ] Unzip the scaffold, `cd smallville-ios`, `git init`, `git add -A`, `git commit -m "Scaffold"`.
- [ ] `cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig` and put your Team ID in it. Change `bundleIdPrefix` in `App/project.yml`.
- [ ] Add the Apple-docs MCP server to the project so the `apple-docs` subagent has tools. You already run sosumi in Claude Desktop; copy its config: `claude mcp add --scope project sosumi -- <same command>` (or the HTTP form if yours is remote). Then run `/mcp` inside Claude Code and check that the tool names match the `tools:` line in `.claude/agents/apple-docs.md`; fix the names if they differ.
- [ ] `claude` in the repo root. Approve the project MCP servers when asked. Run `/context` and look at what loaded: CLAUDE.md, the three rules files (path-scoped, so they only attach when relevant files are touched), two skills, three subagents. Run `/hooks` and confirm the PostToolUse formatter.
- [ ] Read `docs/PROMPTS.md` once.

## Phase 2 — Make the skeleton compile (Opus 5.5, medium effort, ~1 session)

Lever: **a crisp acceptance test**. The Swift in this scaffold was written without a compiler. That is on purpose: the first task is bounded and verifiable, so you can watch how the agent works before trusting it with design.

- [ ] Prompt 1 from PROMPTS.md. Watch for: does it run `swift build` before editing? Does it use the `apple-docs` subagent on `// VERIFY:` lines? Does it try to relax a rule to get past an error?
- [ ] When it reports done, run `swift test` yourself. Read `git diff`. Commit.
- [ ] `/clear`. (Habit: one task, one session.)

## Phase 3 — Plan the core (Fable 5.1, plan mode)

Lever: **plan mode before multi-file work**.

- [ ] `claude --model fable`, Shift+Tab to plan mode, Prompt 2.
- [ ] Review the plan against `docs/ARCHITECTURE.md`. Push back on anything that adds a brain call per tick, grows prompts with town size, or moves `@Generable` into the core. Ask "which test proves this?" for each step.
- [ ] Approve. Let it run. Don't interrupt to micro-steer; queue notes with Enter instead.

## Phase 4 — Implement the core and runner (Fable 5.1, `/goal`)

Lever: **a goal the agent keeps checking itself against**.

- [ ] Prompt 3, with `/goal swift test passes and smallville-run reports withinBudget=true and knows.count>=3 after 2880 minutes with 3 agents`.
- [ ] Before committing, run the `sim-reviewer` subagent (Prompt 4). Fix findings. Commit.

## Phase 5 — Foundation Models adapter on the Mac (Opus 5.5, high effort)

Lever: **verify with the real thing, measure, don't vibe**.

- [ ] Prompt 5. The acceptance test is a 4-hour `--fm` run that completes with `withinBudget=true` and at most a handful of `brainFailures`.
- [ ] Prompt 6: write the first Evaluations-framework eval ("did the invitation propagate?") so quality has a number.

## Phase 6 — App shell (opusplan or Xcode's agent)

Lever: **cheap model for execution, expensive for decisions**.

- [ ] `cd App && xcodegen generate`. Open in Xcode once so signing resolves.
- [ ] Prompt 7 in Xcode's agent or `claude --model opusplan` with XcodeBuildMCP. Acceptance: builds, runs in the iPhone 17 Pro simulator, Discoveries tab shows the stub-brain Valentine's discovery.
- [ ] Benchmark tab working (Prompt 8).

## Phase 7 — Phone (you + Claude)

- [ ] Build to your 17 Pro Max from Xcode. Run Benchmark, share the JSON into the conversation, Prompt 9 (uses the `device-benchmark` skill). Decide the agent-count ceiling from numbers.

## Phase 8 — Assets, attribution, CI

- [ ] Clone `joonspk-research/generative_agents` somewhere; `scripts/fetch-assets.sh /path/to/clone`. Confirm `git status` shows nothing under `Assets/`.
- [ ] Email LimeZu and pipoya (itch.io) about non-commercial open-source use; ask Joon Park about the PixyMoon background. Track answers in `ATTRIBUTION.md`.
- [ ] Push to GitHub; confirm the `swift test` workflow runs on the macOS runner.

## Habits that make the difference

- `/clear` between unrelated tasks; `/rename` first so you can `/resume` later.
- Read every diff before committing. The agent writes the code; you own it.
- When something goes wrong, `Esc` and say what you saw. Double-`Esc` rewinds files and conversation to a checkpoint.
- If the agent keeps violating a rule, the fix is usually in CLAUDE.md or a rules file, not in your prompt. Rules persist; prompts don't.
- `/usage` at the end of a session. Notice what Fable sessions cost versus Opus.
