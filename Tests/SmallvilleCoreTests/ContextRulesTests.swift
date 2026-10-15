import Testing

@testable import SmallvilleCore

/// The rules that bound what goes into a prompt or into memory, checked through the simulation.
@Suite("Context and memory rules")
struct ContextRulesTests {
    private static func storyline(_ id: String, eventMinutes: Int?) -> Storyline {
        Storyline(
            id: StorylineID(id), title: id, seedText: "something about \(id)", seededIn: AgentProfile.isabella.id,
            seededAt: SimTime(minutes: 7 * 60), targetLocation: WorldMap.park,
            eventTime: eventMinutes.map { SimTime(minutes: $0) })
    }

    @Test("the storyline cap keeps upcoming events ahead of past ones")
    func storylineOrdering() async throws {
        let contexts = Recorder<AgentContext>()
        let brain = ScriptedBrain(observe: { await contexts.add($0) })
        var configuration = Simulation.Configuration()
        configuration.maxStorylinesInContext = 2
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: [.isabella], brain: brain, configuration: configuration)
        // Sim starts at 07:00 (minute 420).
        await simulation.whisper(Self.storyline("past-early", eventMinutes: 60))
        await simulation.whisper(Self.storyline("past-late", eventMinutes: 300))
        await simulation.whisper(Self.storyline("undated", eventMinutes: nil))
        await simulation.whisper(Self.storyline("soon", eventMinutes: 600))
        await simulation.whisper(Self.storyline("later", eventMinutes: 2000))
        try await simulation.run(minutes: SimTime.minutesPerTick)

        let first = try #require(await contexts.values.first)
        #expect(first.activeStorylines.map(\.id.rawValue) == ["soon", "later"])
        #expect(first.knownLocations.contains { $0.id == WorldMap.park }, "a known storyline's venue is listed")
    }

    @Test("retention: bouncing between two places does not re-store the same arrival")
    func retention() async throws {
        let home = AgentProfile.isabella.home
        let brain = ScriptedBrain(planHour: { context, _ in
            let place = context.now.hour % 2 == 0 ? WorldMap.hobbsCafe : home
            let activity = context.now.hour % 2 == 0 ? "getting coffee" : "resting"
            return HourPlan(
                hour: context.now.hour,
                actions: [
                    PlannedAction(
                        startMinute: 0, durationMinutes: 60, activity: activity, location: place, emoji: "🙂",
                        event: EventTriple(subject: "Isabella Rodriguez", predicate: "is", object: activity))
                ])
        })
        func arrivals(retention: Int) async throws -> Int {
            var configuration = Simulation.Configuration()
            configuration.perceptionRetention = retention
            let simulation = Simulation(
                world: .smallvilleSubset(), profiles: [.isabella], brain: brain, configuration: configuration)
            try await simulation.run(minutes: 6 * 60)  // 07:00–13:00: cafe at 8, 10, 12
            return await simulation.memories(of: AgentProfile.isabella.id).filter {
                $0.text.hasPrefix("Isabella Rodriguez arrived at Hobbs Cafe")
            }.count
        }
        #expect(try await arrivals(retention: 0) == 3, "without retention every arrival is stored")
        #expect(try await arrivals(retention: 5) == 1, "with retention the repeat arrivals are skipped")
    }

    @Test("a sleeping agent perceives nothing")
    func sleepGate() async throws {
        var (world, pair) = ConversationTests.strangers(acquainted: true)
        pair[1].wakeHour = 9  // Ben sleeps in the shared lounge while Ana is up from 07:00.
        let simulation = Simulation(world: world, profiles: pair, brain: StubBrain())
        try await simulation.run(minutes: 2 * 60)

        let ben = pair[1].id
        let sightings = await simulation.memories(of: ben).filter { $0.text.contains("saw") }
        #expect(sightings.isEmpty)
        let anaSawBen = await simulation.memories(of: pair[0].id).filter { $0.text.contains("saw Ben Osei sleeping") }
        #expect(anaSawBen.count == 1, "the awake one notices the sleeper, once")
    }
}
