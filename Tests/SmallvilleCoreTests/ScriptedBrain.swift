import SmallvilleCore

/// A brain for tests that need one specific answer: each override returns a value or nil to
/// fall through to the stub. `observe` sees every context the simulation builds.
struct ScriptedBrain: AgentBrain {
    var base = StubBrain()
    var observe: (@Sendable (AgentContext) async -> Void)?
    var planHour: (@Sendable (AgentContext, DayPlan) async throws -> HourPlan?)?
    var converse: (@Sendable (ConversationRequest) async throws -> Conversation?)?
    var reflect: (@Sendable (AgentContext) async throws -> [Reflection]?)?
    var ratePoignancy: (@Sendable ([String], AgentProfile) async throws -> [Int]?)?

    private static let receipt = BrainCallReceipt(inputTokens: 300, outputTokens: 60, wallSeconds: 0)

    func planDay(_ context: AgentContext) async throws -> BrainResponse<DayPlan> {
        await observe?(context)
        return try await base.planDay(context)
    }

    func planHour(_ context: AgentContext, dayPlan: DayPlan) async throws -> BrainResponse<HourPlan> {
        await observe?(context)
        if let plan = try await planHour?(context, dayPlan) {
            return BrainResponse(value: plan, receipt: Self.receipt)
        }
        return try await base.planHour(context, dayPlan: dayPlan)
    }

    func converse(_ request: ConversationRequest) async throws -> BrainResponse<Conversation> {
        await observe?(request.initiator)
        if let conversation = try await converse?(request) {
            return BrainResponse(value: conversation, receipt: Self.receipt)
        }
        return try await base.converse(request)
    }

    func reflect(_ context: AgentContext) async throws -> BrainResponse<[Reflection]> {
        await observe?(context)
        if let reflections = try await reflect?(context) {
            return BrainResponse(value: reflections, receipt: Self.receipt)
        }
        return try await base.reflect(context)
    }

    func ratePoignancy(_ texts: [String], for profile: AgentProfile) async throws -> BrainResponse<[Int]> {
        if let ratings = try await ratePoignancy?(texts, profile) {
            return BrainResponse(value: ratings, receipt: Self.receipt)
        }
        return try await base.ratePoignancy(texts, for: profile)
    }
}

/// Collects values from inside `@Sendable` closures without data races.
actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []

    func add(_ value: Value) {
        values.append(value)
    }
}
