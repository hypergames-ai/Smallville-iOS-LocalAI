import Testing

@testable import SmallvilleCore

/// A storyline event has an end: agents attend while it lasts and move on after it.
@Suite("Storyline timing")
struct StorylineTimingTests {
    static func picnic(durationMinutes: Int? = nil) -> Storyline {
        Storyline(
            id: StorylineID("picnic"), title: "a picnic in the park", seedText: "There is a picnic in the park.",
            seededIn: AgentProfile.maria.id, seededAt: SimTime(minutes: 7 * 60), targetLocation: WorldMap.park,
            eventTime: SimTime(minutes: 12 * 60), durationMinutes: durationMinutes)
    }

    @Test("an event is under way from its start up to its end, and over from its end on")
    func underwayAndOver() {
        let party = ValentinesPartyTests.party
        let start = SimTime(minutes: SimTime.minutesPerDay + 17 * 60)
        #expect(party.eventEnd == start.advanced(by: 120))
        #expect(!party.isUnderway(at: start.advanced(by: -10)))
        #expect(party.isUnderway(at: start))
        #expect(party.isUnderway(at: start.advanced(by: 110)))
        #expect(!party.isUnderway(at: start.advanced(by: 120)))
        #expect(!party.isOver(at: start.advanced(by: 110)))
        #expect(party.isOver(at: start.advanced(by: 120)))

        let picnic = Self.picnic()
        #expect(picnic.eventEnd == SimTime(minutes: 13 * 60), "no duration means an hour")
        let untimed = Storyline(
            id: StorylineID("rumor"), title: "a rumor", seedText: "A rumor.", seededIn: AgentProfile.maria.id,
            seededAt: SimTime(minutes: 7 * 60))
        #expect(untimed.eventEnd == nil)
        #expect(!untimed.isUnderway(at: start) && !untimed.isOver(at: start))
    }

    @Test("the stub attends the party for its whole two hours, then leaves and is home by night (seed 7)")
    func attendsWhileItLastsThenLeaves() async throws {
        let simulation = ValentinesPartyTests.makeSimulation()
        await simulation.whisper(ValentinesPartyTests.party)
        try await simulation.run(minutes: 2 * SimTime.minutesPerDay)

        // `.acted` is emitted when an agent's action changes, so an attendee starts attending at
        // 17:00, keeps that action through 18:50, and its next action starts at 19:00.
        let start = SimTime(minutes: SimTime.minutesPerDay + 17 * 60)
        let end = start.advanced(by: 120)
        var acted: [AgentID: [(PlannedAction, SimTime)]] = [:]
        for event in await simulation.events {
            if case .acted(let agent, let action, let at) = event { acted[agent, default: []].append((action, at)) }
        }
        let attendees = acted.filter { _, actions in actions.contains { $0.0.activity.hasPrefix("attending") } }
        #expect(attendees.count >= 2, "the host and at least one guest attend")
        for (agent, actions) in attendees {
            let attending = actions.filter { $0.0.activity.hasPrefix("attending") }.map(\.1)
            #expect(attending == [start], "\(agent) starts attending once, at 17:00")
            let next = actions.first { $0.1 > start }
            #expect(next?.1 == end, "\(agent) moves on at 19:00, not before or after")
        }

        let night = SimTime(minutes: SimTime.minutesPerDay + 22 * 60 + 30)
        let positions = await simulation.positions.filter { $0.at == night }
        for profile in AgentProfile.sample3 {
            #expect(positions.first { $0.agent == profile.id }?.location == profile.home, "\(profile.name) is home")
        }
        let summary = await simulation.budget.summary()
        #expect(summary.withinBudget)
    }

    @Test("an event under way stays in context ahead of upcoming ones, even past the storyline cap")
    func underwayEventSurvivesTheCap() async throws {
        let contexts = Recorder<AgentContext>()
        var brain = ScriptedBrain()
        brain.planHour = { context, _ in
            await contexts.add(context)
            return nil
        }
        var configuration = Simulation.Configuration()
        configuration.maxStorylinesInContext = 2
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: [.maria], brain: brain, configuration: configuration)
        // A three-hour picnic from 12:00, and two events later in the afternoon.
        await simulation.whisper(Self.picnic(durationMinutes: 180))
        for (name, hour) in [("quiz", 16), ("concert", 17)] {
            await simulation.whisper(
                Storyline(
                    id: StorylineID(name), title: name, seedText: "There is a \(name).",
                    seededIn: AgentProfile.maria.id, seededAt: SimTime(minutes: 7 * 60), targetLocation: WorldMap.pub,
                    eventTime: SimTime(minutes: hour * 60)))
        }
        try await simulation.run(minutes: 8 * 60)

        let atOne = try #require(await contexts.values.first { $0.now.hour == 13 })
        #expect(atOne.activeStorylines.map(\.id) == [StorylineID("picnic"), StorylineID("quiz")])
        #expect(await simulation.budget.summary().callsByKind["planHour", default: 0] >= 1)
    }

    @Test("an event's venue leads the location list until the event is over, then drops back")
    func venueDropsBackAfterTheEvent() async throws {
        let contexts = Recorder<AgentContext>()
        var brain = ScriptedBrain()
        brain.planHour = { context, _ in
            await contexts.add(context)
            return nil
        }
        let simulation = Simulation(world: .smallvilleSubset(), profiles: [.maria], brain: brain)
        await simulation.whisper(Self.picnic())
        try await simulation.run(minutes: 7 * 60)

        let maria = AgentProfile.maria
        let byHour = Dictionary(await contexts.values.map { ($0.now.hour, $0) }, uniquingKeysWith: { first, _ in first })
        let during = try #require(byHour[12])
        let after = try #require(byHour[13])
        #expect(
            during.knownLocations.prefix(4).map(\.id) == [maria.workplace, maria.favoriteSpot, WorldMap.park, maria.home])
        #expect(after.knownLocations.prefix(3).map(\.id) == [maria.workplace, maria.favoriteSpot, maria.home])
        #expect(after.knownLocations.contains { $0.id == WorldMap.park }, "the park is still a public place")
        #expect(after.activeStorylines.contains { $0.id == Self.picnic().id }, "an ended event is still known")
        #expect(await simulation.budget.summary().callsByKind["planHour", default: 0] >= 2)
    }
}
