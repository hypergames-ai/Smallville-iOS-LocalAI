import Testing

@testable import SmallvilleCore

/// The original's `revise_identity`: from the second day on, each agent rewrites `currently`
/// at wake, before planning the day.
@Suite("Identity revision")
struct IdentityRevisionTests {
    /// Day 0 from 7:00 through day 1 at 19:00: every agent wakes on day 1 exactly once.
    static let minutes = SimTime.minutesPerDay + 12 * 60

    static func makeSimulation(_ brain: ScriptedBrain) -> Simulation {
        Simulation(world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: brain)
    }

    @Test("no revision on the first day, one per agent at wake on the next, before its day plan")
    func revisesOncePerLaterDayBeforePlanning() async throws {
        let calls = Recorder<String>()
        var brain = ScriptedBrain()
        brain.reviseIdentity = { context in
            await calls.add("revise \(context.profile.id.rawValue) \(context.now.day)")
            return nil
        }
        brain.planDay = { context in
            await calls.add("plan \(context.profile.id.rawValue) \(context.now.day)")
            return nil
        }
        let simulation = Self.makeSimulation(brain)
        try await simulation.run(minutes: Self.minutes)

        let log = await calls.values
        for profile in AgentProfile.sample3 {
            let id = profile.id.rawValue
            #expect(!log.contains("revise \(id) 0"))
            let revise = try #require(log.firstIndex(of: "revise \(id) 1"))
            let plan = try #require(log.firstIndex(of: "plan \(id) 1"))
            #expect(revise < plan)
        }
        let summary = await simulation.budget.summary()
        #expect(summary.callsByKind["reviseIdentity"] == AgentProfile.sample3.count)
        #expect(summary.withinBudget)
    }

    @Test("the revised status reaches the day plan, later hour plans and the profile")
    func revisedStatusPropagates() async throws {
        let revised = "Klaus Mueller plans to go to the Valentine's party at Hobbs Cafe at 17:00."
        let seen = Recorder<String>()
        var brain = ScriptedBrain()
        brain.reviseIdentity = { context in
            guard context.profile.id == AgentProfile.klaus.id else { return nil }
            return IdentityRevision(planNote: "Go to the party.", thoughtNote: "Excited.", currently: revised)
        }
        brain.planDay = { context in
            if context.profile.id == AgentProfile.klaus.id, context.now.day == 1 {
                await seen.add("plan \(context.profile.currently)")
            }
            return nil
        }
        brain.planHour = { context, _ in
            if context.profile.id == AgentProfile.klaus.id, context.now.day == 1, context.now.hour == 12 {
                await seen.add("hour \(context.profile.currently)")
            }
            return nil
        }
        let simulation = Self.makeSimulation(brain)
        try await simulation.run(minutes: Self.minutes)

        #expect(await seen.values == ["plan \(revised)", "hour \(revised)"])
        #expect(await simulation.profile(of: AgentProfile.klaus.id)?.currently == revised)
        let notes = await simulation.memories(of: AgentProfile.klaus.id).filter {
            $0.text.hasPrefix("Klaus Mueller's note for today:")
        }
        #expect(notes.count == 1)
        #expect(await simulation.budget.summary().callsByKind["reviseIdentity"] == AgentProfile.sample3.count)
    }

    @Test("a long revised status is capped before it reaches later prompts")
    func revisedStatusIsCapped() async throws {
        let long = String(repeating: "Klaus has a lot on his mind. ", count: 40)
        var brain = ScriptedBrain()
        brain.reviseIdentity = { _ in IdentityRevision(planNote: "", thoughtNote: "", currently: long) }
        let simulation = Self.makeSimulation(brain)
        try await simulation.run(minutes: Self.minutes)

        let limit = Simulation.Configuration().maxCurrentlyCharacters
        #expect(await simulation.profile(of: AgentProfile.klaus.id)?.currently == String(long.prefix(limit)))
        #expect(await simulation.budget.summary().withinBudget)
    }

    @Test("a refused revision keeps the old status and the day is still planned")
    func refusedRevisionIsSkipped() async throws {
        var brain = ScriptedBrain()
        brain.reviseIdentity = { _ in throw BrainError.refused("guardrail") }
        let simulation = Self.makeSimulation(brain)
        try await simulation.run(minutes: Self.minutes)

        let failures = await simulation.events.filter { event in
            if case .brainFailed(_, .reviseIdentity, _, _) = event { return true }
            return false
        }
        #expect(failures.count == AgentProfile.sample3.count)
        #expect(await simulation.profile(of: AgentProfile.klaus.id)?.currently == AgentProfile.klaus.currently)
        let summary = await simulation.budget.summary()
        #expect(summary.callsByKind["planDay"] == 2 * AgentProfile.sample3.count)
        #expect(summary.callsByKind["reviseIdentity", default: 0] == 0)
    }

    // Depends on the default seed (42): the stub spreads the invite to everyone on day 0.
    @Test("an invitation heard on day 0 is in the agent's day-1 revision context (seed 42)")
    func invitationReachesRevision() async throws {
        let contexts = Recorder<AgentContext>()
        var brain = ScriptedBrain()
        brain.reviseIdentity = { context in
            await contexts.add(context)
            return nil
        }
        let simulation = Self.makeSimulation(brain)
        await simulation.whisper(ValentinesPartyTests.party)
        try await simulation.run(minutes: Self.minutes)

        let party = ValentinesPartyTests.party.id
        let revisions = await contexts.values
        #expect(revisions.count == AgentProfile.sample3.count)
        for context in revisions {
            #expect(context.activeStorylines.contains { $0.id == party })
            #expect(
                context.relevantMemories.contains { $0.storylines.contains(party) },
                "\(context.profile.name) should recall the party when revising")
        }
        #expect(await simulation.budget.summary().callsByKind["reviseIdentity"] == AgentProfile.sample3.count)
    }
}
