import Testing

@testable import SmallvilleCore

@Suite("Reflection triggers")
struct ReflectionTests {
    private static func reflections(of agent: AgentID, in events: [SimEvent]) -> [(Reflection, SimTime)] {
        events.compactMap { event in
            if case .reflected(let who, let reflection, let at) = event, who == agent { return (reflection, at) }
            return nil
        }
    }

    @Test("a flood of important memories still yields at most the daily cap, spaced an hour apart")
    func capAndSpacing() async throws {
        // Everything is life-changing, so the importance threshold is crossed almost every tick.
        let brain = ScriptedBrain(ratePoignancy: { texts, _ in texts.map { _ in 10 } })
        var configuration = Simulation.Configuration()
        configuration.reflectionImportanceThreshold = 20
        configuration.maxReflectionsPerAgentDay = 3
        configuration.reflectionSpacingMinutes = 60
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: brain, configuration: configuration)
        try await simulation.run(minutes: 2 * SimTime.minutesPerDay)

        let events = await simulation.events
        for profile in AgentProfile.sample3 {
            let times = Self.reflections(of: profile.id, in: events).map(\.1)
            #expect(!times.isEmpty, "\(profile.id) reflects at all")
            for day in 0..<2 {
                #expect(times.filter { $0.day == day }.count <= 3, "\(profile.id) day \(day)")
            }
            for (earlier, later) in zip(times, times.dropFirst()) {
                #expect(later.minutes - earlier.minutes >= 60)
            }
        }
        let summary = await simulation.budget.summary()
        #expect(summary.callsByKind["reflect", default: 0] <= 3 * summary.agentDays)
        #expect(summary.withinBudget)
    }

    @Test("reflection waits for the importance threshold")
    func thresholdGate() async throws {
        var configuration = Simulation.Configuration()
        configuration.reflectionImportanceThreshold = 1000
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: StubBrain(), configuration: configuration
        )
        try await simulation.run(minutes: SimTime.minutesPerDay)
        #expect(await simulation.budget.summary().callsByKind["reflect", default: 0] == 0)
    }

    @Test("evidence the agent does not have is dropped, and an insight with no evidence is dropped whole")
    func evidenceFiltering() async throws {
        let brain = ScriptedBrain(reflect: { context in
            let real = context.relevantMemories.first.map(\.id) ?? 0
            return [
                Reflection(insight: "half real", evidence: [real, 999_999]),
                Reflection(insight: "made up", evidence: [999_998]),
            ]
        })
        var configuration = Simulation.Configuration()
        configuration.reflectionImportanceThreshold = 10
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: [.isabella], brain: brain, configuration: configuration)
        try await simulation.run(minutes: SimTime.minutesPerDay)

        let stored = await simulation.memories(of: AgentProfile.isabella.id).filter { $0.kind == .reflection }
        #expect(!stored.isEmpty)
        #expect(stored.allSatisfy { $0.text == "half real" })
        for node in stored {
            guard case .reflected(let from) = node.provenance else {
                Issue.record("reflections are reflected-from")
                continue
            }
            #expect(from.count == 1)
            #expect(!from.contains(999_999))
        }
        let recorded = Self.reflections(of: AgentProfile.isabella.id, in: await simulation.events)
        #expect(recorded.allSatisfy { $0.0.insight == "half real" && $0.0.evidence.count == 1 })
    }

    @Test("a reflection over a storyline memory carries the tag, so knowledge survives reflection (stub, seed 7)")
    func reflectionInheritsStorylines() async throws {
        let simulation = ValentinesPartyTests.makeSimulation()
        await simulation.whisper(ValentinesPartyTests.party)
        try await simulation.run(minutes: 2 * SimTime.minutesPerDay)

        let party = ValentinesPartyTests.party.id
        var taggedReflections = 0
        for profile in AgentProfile.sample3 {
            let nodes = await simulation.memories(of: profile.id)
            for node in nodes where node.kind == .reflection {
                guard case .reflected(let from) = node.provenance else { continue }
                let citesParty = from.contains { id in nodes.first { $0.id == id }?.storylines.contains(party) == true }
                #expect(node.storylines.contains(party) == citesParty)
                if citesParty { taggedReflections += 1 }
            }
        }
        #expect(taggedReflections > 0, "someone reflects on the party")
        let discovery = try #require(await simulation.discoveries().first)
        let allEvidence = Set(discovery.evidence.values.flatMap { $0 })
        #expect(!allEvidence.isEmpty)
    }

    @Test("reflections are rated by the next poignancy batch instead of keeping a fixed score")
    func reflectionsGetRated() async throws {
        let rated = Recorder<String>()
        let brain = ScriptedBrain(ratePoignancy: { texts, _ in
            for text in texts { await rated.add(text) }
            return texts.map { _ in 4 }
        })
        var configuration = Simulation.Configuration()
        configuration.reflectionImportanceThreshold = 10
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: brain, configuration: configuration)
        try await simulation.run(minutes: SimTime.minutesPerDay)

        let insights = Self.reflections(of: AgentProfile.isabella.id, in: await simulation.events).map(\.0.insight)
        #expect(!insights.isEmpty)
        let seen = await rated.values
        #expect(insights.allSatisfy { seen.contains($0) })
    }

    @Test(
        "real ratings, not default scores, decide whether the threshold is reached",
        arguments: [(10, true), (1, false)])
    func ratingsDriveTheThreshold(rating: Int, reflects: Bool) async throws {
        // One agent alone stores ~10 memories a day: ~25 importance on default scores, ~15 rated 1,
        // ~78 rated 10. A threshold of 40 is reached only when real ratings count.
        let brain = ScriptedBrain(ratePoignancy: { texts, _ in texts.map { _ in rating } })
        var configuration = Simulation.Configuration()
        configuration.reflectionImportanceThreshold = 40
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: [.isabella], brain: brain, configuration: configuration)
        try await simulation.run(minutes: SimTime.minutesPerDay)

        let reflections = Self.reflections(of: AgentProfile.isabella.id, in: await simulation.events)
        #expect(reflections.isEmpty != reflects, "rating \(rating)")
    }
}
