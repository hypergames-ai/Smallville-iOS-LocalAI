import Testing

@testable import SmallvilleCore

@Suite("Hourly planner")
struct HourPlanTests {
    private static func action(start: Int, _ activity: String, at location: LocationID = WorldMap.hobbsCafe)
        -> PlannedAction
    {
        PlannedAction(
            startMinute: start, durationMinutes: 10, activity: activity, location: location, emoji: "🙂",
            event: EventTriple(subject: "x", predicate: "is", object: activity))
    }

    @Test("normalization sorts, dedupes, pulls the first action to minute 0 and fills every minute")
    func normalization() {
        let plan = HourPlan(
            hour: 9,
            actions: [
                Self.action(start: 45, "late"), Self.action(start: 10, "first"), Self.action(start: 10, "duplicate"),
                Self.action(start: 99, "clamped"),
            ])
        let normalized = plan.normalized(hour: 9)

        #expect(normalized.actions.map(\.activity) == ["first", "late", "clamped"])
        #expect(normalized.actions.map(\.startMinute) == [0, 40, 50], "snapped to the 10-minute tick grid")
        #expect(normalized.actions.map(\.durationMinutes) == [40, 10, 10])
        for minute in 0..<60 {
            #expect(normalized.action(atMinute: minute) != nil)
        }
        #expect(HourPlan(hour: 9, actions: []).normalized(hour: 9).actions.isEmpty)
    }

    @Test("a location given by name resolves; an unknown one falls back to the previous action's place")
    func locationResolution() async throws {
        let brain = ScriptedBrain(planHour: { context, _ in
            guard context.now.hour == 7 else { return nil }
            return HourPlan(
                hour: 7,
                actions: [
                    Self.action(start: 0, "open up", at: LocationID("Hobbs Cafe")),
                    Self.action(start: 30, "moonwalk", at: LocationID("the_moon")),
                ])
        })
        let simulation = Simulation(world: .smallvilleSubset(), profiles: [.isabella], brain: brain)
        try await simulation.run(minutes: 60)

        let events = await simulation.events
        let acted = events.compactMap { event -> (PlannedAction, SimTime)? in
            if case .acted(_, let action, let at) = event { return (action, at) }
            return nil
        }
        let moved = events.compactMap { event -> (LocationID, SimTime)? in
            if case .moved(_, let to, let at) = event { return (to, at) }
            return nil
        }
        #expect(acted.map(\.0.location) == [WorldMap.hobbsCafe, WorldMap.hobbsCafe])
        #expect(moved.count == 1, "one move: home to the cafe; the unknown place does not teleport anyone")
        #expect(moved.first?.0 == WorldMap.hobbsCafe)
        #expect(moved.first?.1 == acted.first?.1.advanced(by: SimTime.minutesPerTick), "arrival takes one tick")
    }

    @Test("the location list is capped and always holds the agent's own places and the storyline venue")
    func knownLocationsAreCapped() async throws {
        var locations = WorldMap.smallvilleSubset().allLocations
        for index in 0..<30 {
            locations.append(
                Location(
                    id: LocationID("the_ville:extra_\(index)"), name: "Extra \(index)", sector: "Extra", arena: "room",
                    objects: [], isPublic: true))
        }
        let contexts = Recorder<AgentContext>()
        let brain = ScriptedBrain(observe: { await contexts.add($0) })
        var configuration = Simulation.Configuration()
        configuration.maxLocationsInContext = 6
        let simulation = Simulation(
            world: WorldMap(locations: locations), profiles: [.maria], brain: brain, configuration: configuration)
        await simulation.whisper(ValentinesPartyTests.party)
        try await simulation.run(minutes: 3 * 60)

        let seen = await contexts.values
        #expect(!seen.isEmpty)
        for context in seen {
            let ids = Set(context.knownLocations.map(\.id))
            #expect(context.knownLocations.count <= 6)
            #expect(ids.isSuperset(of: [AgentProfile.maria.home, AgentProfile.maria.workplace, WorldMap.hobbsCafe]))
        }
    }

    @Test("the stub's split hours produce two actions and the day plan entry travels in the context")
    func stubDecomposition() async throws {
        let contexts = Recorder<AgentContext>()
        let brain = ScriptedBrain(observe: { await contexts.add($0) })
        let simulation = Simulation(world: .smallvilleSubset(), profiles: [.klaus], brain: brain)
        try await simulation.run(minutes: 24 * 60)

        let events = await simulation.events
        let lunchActions = events.compactMap { event -> PlannedAction? in
            if case .acted(_, let action, let at) = event, at.hour == 13 { return action }
            return nil
        }
        #expect(lunchActions.map(\.startMinute) == [0, 30])
        #expect(lunchActions.map(\.durationMinutes) == [30, 30])

        let entries = await contexts.values.compactMap { $0.now.hour == 13 ? $0.currentEntry : nil }
        #expect(entries.allSatisfy { $0.hour == 13 && $0.activity.contains("lunch") })
    }
}
