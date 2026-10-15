#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SmallvilleCore

/// Drives one on-device `LanguageModelSession` per agent. Every call uses guided generation
/// and is mapped into the core's plain types; token counts and wall time come back as receipts.
@available(iOS 26.0, macOS 26.0, *)
public actor FoundationModelsBrain: AgentBrain {
    private let model: SystemLanguageModel
    private var sessions: [AgentID: LanguageModelSession] = [:]

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    // MARK: - AgentBrain

    public func planDay(_ context: AgentContext) async throws -> BrainResponse<DayPlan> {
        let (generated, receipt) = try await respond(
            for: context.profile, prompt: Prompts.dayPlan(context), generating: GeneratedDayPlan.self)
        let plan = DayPlan(
            wakeHour: generated.wakeHour,
            entries: generated.entries.map { DayPlanEntry(hour: $0.hour, activity: $0.activity) })
        return BrainResponse(value: plan, receipt: receipt)
    }

    public func planHour(_ context: AgentContext, dayPlan: DayPlan) async throws -> BrainResponse<HourPlan> {
        let (generated, receipt) = try await respond(
            for: context.profile, prompt: Prompts.hourPlan(context, dayPlan: dayPlan),
            generating: GeneratedHourPlan.self)
        let actions = generated.actions.map { action in
            PlannedAction(
                startMinute: action.startMinute, durationMinutes: action.durationMinutes, activity: action.activity,
                location: LocationID(action.locationID), emoji: action.emoji,
                event: EventTriple(subject: action.subject, predicate: action.predicate, object: action.object))
        }
        return BrainResponse(value: HourPlan(hour: context.now.hour, actions: actions), receipt: receipt)
    }

    public func converse(_ request: ConversationRequest) async throws -> BrainResponse<Conversation> {
        let a = request.initiator.profile
        let b = request.partner.profile
        let (generated, receipt) = try await respond(
            for: a, prompt: Prompts.conversation(request), generating: GeneratedConversation.self)

        func agent(named name: String) -> AgentID {
            name.localizedCaseInsensitiveContains(b.name.split(separator: " ").first.map(String.init) ?? b.name)
                ? b.id : a.id
        }

        let turns = generated.turns.map { ConversationTurn(speaker: agent(named: $0.speaker), text: $0.text) }
        let acts = generated.acts.compactMap { act -> SocialAct? in
            guard let kind = SocialActKind(rawValue: act.kind) else { return nil }
            return SocialAct(
                kind: kind, from: agent(named: act.from), to: agent(named: act.to), topic: act.topic,
                storyline: act.storylineID.isEmpty ? nil : StorylineID(act.storylineID))
        }
        let conversation = Conversation(
            initiator: a.id, partner: b.id, turns: turns, acts: acts,
            conveyedStorylines: generated.conveyedStorylineIDs.filter { !$0.isEmpty }.map { StorylineID($0) },
            initiatorSummary: generated.initiatorSummary, partnerSummary: generated.partnerSummary)
        return BrainResponse(value: conversation, receipt: receipt)
    }

    public func reflect(_ context: AgentContext) async throws -> BrainResponse<[Reflection]> {
        let (generated, receipt) = try await respond(
            for: context.profile, prompt: Prompts.reflection(context), generating: GeneratedReflections.self)
        let known = Set(context.relevantMemories.map(\.id))
        let reflections = generated.insights.map {
            Reflection(insight: $0.insight, evidence: $0.evidence.filter { known.contains($0) })
        }
        return BrainResponse(value: reflections, receipt: receipt)
    }

    public func ratePoignancy(_ texts: [String], for profile: AgentProfile) async throws -> BrainResponse<[Int]> {
        guard !texts.isEmpty else {
            return BrainResponse(
                value: [], receipt: BrainCallReceipt(inputTokens: 0, outputTokens: 0, wallSeconds: 0))
        }
        let (generated, receipt) = try await respond(
            for: profile, prompt: Prompts.poignancy(texts, for: profile), generating: GeneratedRatings.self)
        var ratings = generated.ratings.map { max(1, min(10, $0)) }
        if ratings.count < texts.count {
            ratings += Array(repeating: 3, count: texts.count - ratings.count)
        }
        return BrainResponse(value: Array(ratings.prefix(texts.count)), receipt: receipt)
    }

    // MARK: - Sessions

    private func session(for profile: AgentProfile) throws -> LanguageModelSession {
        if let existing = sessions[profile.id] {
            return existing
        }
        guard model.isAvailable else {
            throw BrainError.unavailable(String(describing: model.availability))
        }
        let session = LanguageModelSession(
            model: model, instructions: Instructions(Prompts.instructions(for: profile)))
        session.prewarm()
        sessions[profile.id] = session
        return session
    }

    private func resetSession(for profile: AgentProfile) {
        sessions[profile.id] = nil
    }

    /// One guided-generation call with error mapping, one retry on context overflow, and a receipt.
    private func respond<Content: Generable>(
        for profile: AgentProfile, prompt: String, generating type: Content.Type, isRetry: Bool = false
    ) async throws -> (Content, BrainCallReceipt) {
        let session = try session(for: profile)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await session.respond(to: prompt, generating: type)
            let elapsed = clock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return (response.content, receipt(for: response, prompt: prompt, seconds: seconds))
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize where !isRetry:
                resetSession(for: profile)
                return try await respond(for: profile, prompt: prompt, generating: type, isRetry: true)
            case .guardrailViolation, .refusal:
                throw BrainError.refused(error.localizedDescription)
            case .assetsUnavailable:
                throw BrainError.unavailable(error.localizedDescription)
            default:
                throw BrainError.malformed(error.localizedDescription)
            }
        }
    }

    private func receipt<Content: Generable>(
        for response: LanguageModelSession.Response<Content>, prompt: String, seconds: Double
    ) -> BrainCallReceipt {
        if #available(iOS 27.0, macOS 27.0, *) {
            return BrainCallReceipt(
                inputTokens: response.usage.input.totalTokenCount,
                outputTokens: response.usage.output.totalTokenCount, wallSeconds: seconds)
        }
        // iOS 26 has no usage on the response; estimate so the budget still has a number.
        return BrainCallReceipt(inputTokens: prompt.count / 4 + 400, outputTokens: 150, wallSeconds: seconds)
    }
}
#endif
