import Testing

@testable import SmallvilleCore

@Suite("Perception")
struct PerceptionTests {
    private static func observations(of agent: AgentID, in simulation: Simulation, containing fragment: String) async
        -> [MemoryNode]
    {
        await simulation.memories(of: agent).filter { $0.kind == .observation && $0.text.contains(fragment) }
    }

    @Test("agents remember their own actions and each other's, once per distinct activity (stub)")
    func lunchAtTheCafe() async throws {
        let simulation = Simulation(world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: StubBrain())
        try await simulation.run(minutes: 24 * 60)

        let klaus = AgentProfile.klaus.id
        #expect(
            await Self.observations(of: klaus, in: simulation, containing: "Klaus Mueller is having lunch").count == 1)
        #expect(
            await Self.observations(of: klaus, in: simulation, containing: "saw Maria Lopez having lunch").count == 1)
        #expect(
            await Self.observations(of: klaus, in: simulation, containing: "saw Maria Lopez chatting over coffee").count
                == 1)
        #expect(await Self.observations(of: klaus, in: simulation, containing: "saw Isabella Rodriguez").count >= 1)
    }

    @Test("someone who has set off is not seen doing the thing they left to do")
    func travelersAreNotPerceived() async throws {
        // Maria and Klaus are at the library at 09:00; at 10:00 Maria sets off for the cafe.
        let brain = ScriptedBrain(planHour: { context, _ in
            guard context.profile.id == AgentProfile.maria.id, context.now.hour == 10 else { return nil }
            return HourPlan(
                hour: 10,
                actions: [
                    PlannedAction(
                        startMinute: 0, durationMinutes: 60, activity: "getting a coffee", location: WorldMap.hobbsCafe,
                        emoji: "☕️",
                        event: EventTriple(subject: "Maria Lopez", predicate: "is", object: "getting a coffee"))
                ])
        })
        let simulation = Simulation(world: .smallvilleSubset(), profiles: [.klaus, .maria], brain: brain)
        try await simulation.run(minutes: 4 * 60)  // 07:00 through 11:00

        let sightings = await Self.observations(
            of: AgentProfile.klaus.id, in: simulation, containing: "saw Maria Lopez getting a coffee")
        #expect(sightings.isEmpty, "she was on her way out, not getting coffee in the library")
    }

    @Test("parting and meeting again makes the same activity worth noticing again")
    func reperceptionAfterParting() async throws {
        // Maria leaves the library for the cafe at 10:00 and is back at 11:00; Klaus stays.
        let brain = ScriptedBrain(planHour: { context, _ in
            guard context.profile.id == AgentProfile.maria.id, context.now.hour == 10 else { return nil }
            return HourPlan(
                hour: 10,
                actions: [
                    PlannedAction(
                        startMinute: 0, durationMinutes: 60, activity: "getting a coffee", location: WorldMap.hobbsCafe,
                        emoji: "☕️",
                        event: EventTriple(subject: "Maria Lopez", predicate: "is", object: "getting a coffee"))
                ])
        })
        let simulation = Simulation(world: .smallvilleSubset(), profiles: [.klaus, .maria], brain: brain)
        try await simulation.run(minutes: 6 * 60)  // 07:00 through 13:00

        let sightings = await Self.observations(
            of: AgentProfile.klaus.id, in: simulation, containing: "saw Maria Lopez working as")
        #expect(sightings.count == 2, "once when they arrive together, once when she comes back")
        #expect(sightings.map(\.created.hour) == [9, 11])
    }

    @Test("the poignancy batch is capped and the remainder is rated later")
    func batchCap() async throws {
        let sizes = Recorder<Int>()
        let brain = ScriptedBrain(ratePoignancy: { texts, _ in
            await sizes.add(texts.count)
            return texts.map { _ in 3 }
        })
        var configuration = Simulation.Configuration()
        configuration.maxPoignancyBatch = 3
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: brain, configuration: configuration)
        try await simulation.run(minutes: 24 * 60)

        let recorded = await sizes.values
        #expect(!recorded.isEmpty)
        #expect(recorded.allSatisfy { $0 <= 3 })
        #expect(recorded.reduce(0, +) > 3, "more than one batch ran")
    }
}
