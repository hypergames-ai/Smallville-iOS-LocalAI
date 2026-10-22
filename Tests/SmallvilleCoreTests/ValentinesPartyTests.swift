import Testing

@testable import SmallvilleCore

/// The acceptance test for the whole project, run against the stub brain: plant the party in
/// Isabella, run two game-days, and check that the detector can see it spread.
@Suite("Valentine's party propagation (stub brain)")
struct ValentinesPartyTests {
    static let party = Storyline(
        id: StorylineID("valentines-party"),
        title: "Valentine's Day party at Hobbs Cafe",
        seedText:
            "Isabella is throwing a Valentine's Day party at Hobbs Cafe tomorrow from 5pm to 7pm and wants to invite everyone she knows.",
        seededIn: AgentProfile.isabella.id,
        seededAt: SimTime(minutes: 7 * 60),
        targetLocation: WorldMap.hobbsCafe,
        eventTime: SimTime(minutes: SimTime.minutesPerDay + 17 * 60), durationMinutes: 120)

    static func makeSimulation(seed: UInt64 = 7) -> Simulation {
        var configuration = Simulation.Configuration()
        configuration.seed = seed
        return Simulation(
            world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: StubBrain(),
            configuration: configuration)
    }

    @Test("the invitation spreads and people show up")
    func invitationSpreadsAndPeopleShowUp() async throws {
        let simulation = Self.makeSimulation()
        await simulation.whisper(Self.party)
        try await simulation.run(minutes: 2 * SimTime.minutesPerDay)

        let discovery = try #require(await simulation.discoveries().first)
        #expect(discovery.knows.count == 3, "everyone should have heard about the party")
        #expect(!discovery.diffusion.isEmpty, "there should be a told-by chain")
        #expect(discovery.invited.count >= 1)
        #expect(discovery.host == AgentProfile.isabella.id)
        #expect(discovery.attended.contains(discovery.host))
        #expect(discovery.attended.count >= 2, "at least one invitee should be at the cafe at 5pm on day 2")
    }

    @Test("two game-days stay within the call budget")
    func staysWithinCallBudget() async throws {
        let simulation = Self.makeSimulation()
        await simulation.whisper(Self.party)
        try await simulation.run(minutes: 2 * SimTime.minutesPerDay)

        let summary = await simulation.budget.summary()
        #expect(summary.withinBudget)
        #expect(summary.maxCallsPerAgentDay <= CallBudget.maxCallsPerAgentDay)
        #expect(summary.callsByKind["planHour", default: 0] > 0)
        #expect(
            summary.callsByKind["planHour", default: 0] <= 16 * summary.agentDays,
            "one hour-plan call per waking hour, wake 6 to sleep 22")
    }

    @Test("same seed and whispers replay to identical events (seed 3)")
    func replaysDeterministically() async throws {
        let first = Self.makeSimulation(seed: 3)
        let second = Self.makeSimulation(seed: 3)
        await first.whisper(Self.party)
        await second.whisper(Self.party)
        try await first.run(minutes: SimTime.minutesPerDay)
        try await second.run(minutes: SimTime.minutesPerDay)

        let firstEvents = await first.events
        let secondEvents = await second.events
        #expect(firstEvents == secondEvents)
        #expect(!firstEvents.isEmpty)
    }

    @Test("a refused brain call is skipped, not fatal")
    func refusedCallIsSkipped() async throws {
        struct RefusingBrain: AgentBrain {
            let inner = StubBrain()
            func reviseIdentity(_ context: AgentContext) async throws -> BrainResponse<IdentityRevision> {
                try await inner.reviseIdentity(context)
            }
            func planDay(_ context: AgentContext) async throws -> BrainResponse<DayPlan> {
                try await inner.planDay(context)
            }
            func planHour(_ context: AgentContext, dayPlan: DayPlan) async throws -> BrainResponse<HourPlan> {
                try await inner.planHour(context, dayPlan: dayPlan)
            }
            func converse(_ request: ConversationRequest) async throws -> BrainResponse<Conversation> {
                throw BrainError.refused("guardrail")
            }
            func reflect(_ context: AgentContext) async throws -> BrainResponse<[Reflection]> {
                try await inner.reflect(context)
            }
            func ratePoignancy(_ texts: [String], for profile: AgentProfile) async throws -> BrainResponse<[Int]> {
                try await inner.ratePoignancy(texts, for: profile)
            }
        }

        let simulation = Simulation(world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: RefusingBrain())
        await simulation.whisper(Self.party)
        try await simulation.run(minutes: SimTime.minutesPerDay)

        let snapshot = await simulation.snapshot()
        #expect(snapshot.brainFailures > 0)
        let discovery = try #require(await simulation.discoveries().first)
        #expect(discovery.knows == [AgentProfile.isabella.id], "nothing spreads when every conversation is refused")
    }
}
