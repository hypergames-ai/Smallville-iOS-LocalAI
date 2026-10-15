#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SmallvilleCore
import os

/// Answers the simulation's decisions with the on-device model. Each call is a fresh
/// `LanguageModelSession` with the agent's persona as instructions (ADR 13), uses guided
/// generation, and is mapped into the core's plain types with a receipt of its real token cost.
@available(iOS 26.0, macOS 26.0, *)
public actor FoundationModelsBrain: AgentBrain {
    private let model: SystemLanguageModel
    private let log = Logger(subsystem: "smallville", category: "fm")

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    // MARK: - AgentBrain

    public func planDay(_ context: AgentContext) async throws -> BrainResponse<DayPlan> {
        let (generated, receipt) = try await respond(
            .planDay, for: context.profile, decoding: GeneratedDayPlan.self
        ) { Prompts.dayPlan(context, memoryLimit: $0) }
        let plan = DayPlan(
            wakeHour: generated.wakeHour,
            entries: generated.entries.map { DayPlanEntry(hour: $0.hour, activity: $0.activity) })
        return BrainResponse(value: plan, receipt: receipt)
    }

    public func planHour(_ context: AgentContext, dayPlan: DayPlan) async throws -> BrainResponse<HourPlan> {
        var locationIDs = context.knownLocations.map(\.id.rawValue)
        if locationIDs.isEmpty {
            locationIDs = [context.location.id.rawValue]
        }
        let schema = try makeSchema { try DynamicSchemas.hourPlan(locationIDs: locationIDs) }
        let (generated, receipt) = try await respond(
            .planHour, for: context.profile, schema: schema, decoding: GeneratedHourPlan.self
        ) { Prompts.hourPlan(context, dayPlan: dayPlan, memoryLimit: $0) }
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
        var storylineIDs: [String] = []
        for storyline in request.initiator.activeStorylines + request.partner.activeStorylines
        where !storylineIDs.contains(storyline.id.rawValue) {
            storylineIDs.append(storyline.id.rawValue)
        }
        let schema = try makeSchema {
            try DynamicSchemas.conversation(
                names: [a.name, b.name], storylineIDs: storylineIDs, maxTurns: request.maxTurns)
        }
        let (generated, receipt) = try await respond(
            .converse, for: a, schema: schema, decoding: GeneratedConversation.self, memoryLimit: 5
        ) { Prompts.conversation(request, memoryLimit: $0) }

        // The schema limits names to these two, so anything else cannot happen; the initiator is a safe default.
        func agent(named name: String) -> AgentID {
            name == b.name ? b.id : a.id
        }
        func storyline(_ raw: String) -> StorylineID? {
            raw == DynamicSchemas.noStoryline ? nil : StorylineID(raw)
        }

        let turns = generated.turns.map { ConversationTurn(speaker: agent(named: $0.speaker), text: $0.text) }
        let acts = generated.acts.compactMap { act -> SocialAct? in
            guard let kind = SocialActKind(rawValue: act.kind) else { return nil }
            return SocialAct(
                kind: kind, from: agent(named: act.from), to: agent(named: act.to), topic: act.topic,
                storyline: storyline(act.storylineID))
        }
        var conveyed: [StorylineID] = []
        for id in generated.conveyedStorylineIDs.compactMap(storyline) where !conveyed.contains(id) {
            conveyed.append(id)
        }
        let conversation = Conversation(
            initiator: a.id, partner: b.id, turns: turns, acts: acts, conveyedStorylines: conveyed,
            initiatorSummary: generated.initiatorSummary, partnerSummary: generated.partnerSummary)
        return BrainResponse(value: conversation, receipt: receipt)
    }

    public func reflect(_ context: AgentContext) async throws -> BrainResponse<[Reflection]> {
        let (generated, receipt) = try await respond(
            .reflect, for: context.profile, decoding: GeneratedReflections.self
        ) { Prompts.reflection(context, memoryLimit: $0) }
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
            .ratePoignancy, for: profile, decoding: GeneratedRatings.self, memoryLimit: 0
        ) { _ in Prompts.poignancy(texts, for: profile) }
        var ratings = generated.ratings.map { max(1, min(10, $0)) }
        if ratings.count < texts.count {
            ratings += Array(repeating: 3, count: texts.count - ratings.count)
        }
        return BrainResponse(value: Array(ratings.prefix(texts.count)), receipt: receipt)
    }

    // MARK: - One call

    /// One guided-generation call in a fresh session. With a `schema`, the model fills that
    /// runtime schema and the result is decoded into `Content`; without one, `Content`'s own
    /// schema is used. A context overflow is retried once with half the retrieved memories; a
    /// prompt without memories (`memoryLimit` 0 or 1) is not retried.
    private func respond<Content: Generable>(
        _ kind: BrainCallKind, for profile: AgentProfile, schema: GenerationSchema? = nil,
        decoding type: Content.Type, memoryLimit: Int = Prompts.defaultMemoryLimit,
        prompt: (Int) -> String
    ) async throws -> (Content, BrainCallReceipt) {
        guard model.isAvailable else {
            throw BrainError.unavailable(String(describing: model.availability))
        }
        let instructions = Prompts.instructions(for: profile)
        var limit = memoryLimit
        var retried = false
        while true {
            let text = prompt(limit)
            let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let content: Content
                let receipt: BrainCallReceipt
                if let schema {
                    let response = try await session.respond(to: text, schema: schema)
                    content = try Content(response.content)
                    receipt = await self.receipt(
                        for: response, instructions: instructions, prompt: text, schema: schema,
                        seconds: seconds(since: start, clock))
                } else {
                    let response = try await session.respond(to: text, generating: type)
                    content = response.content
                    receipt = await self.receipt(
                        for: response, instructions: instructions, prompt: text, schema: Content.generationSchema,
                        seconds: seconds(since: start, clock))
                }
                log.debug(
                    "\(kind.rawValue, privacy: .public) \(profile.id.rawValue, privacy: .public): in \(receipt.inputTokens) out \(receipt.outputTokens) \(receipt.wallSeconds, format: .fixed(precision: 1))s"
                )
                return (content, receipt)
            } catch {
                switch Self.classify(error) {
                case .contextExceeded(let detail) where !retried && limit > 1:
                    log.notice(
                        "\(kind.rawValue, privacy: .public): context exceeded (\(detail, privacy: .public)); retrying with \(limit / 2) memories"
                    )
                    limit /= 2
                    retried = true
                case .contextExceeded(let detail):
                    throw fail(kind, BrainError.malformed("context exceeded: \(detail)"))
                case .brain(let brainError):
                    throw fail(kind, brainError)
                case .cancelled:
                    throw error
                }
            }
        }
    }

    private func makeSchema(_ build: () throws -> GenerationSchema) throws -> GenerationSchema {
        do {
            return try build()
        } catch {
            throw fail(nil, BrainError.malformed("schema: \(error)"))
        }
    }

    private func fail(_ kind: BrainCallKind?, _ error: BrainError) -> BrainError {
        log.error(
            "\(kind?.rawValue ?? "schema", privacy: .public) failed: \(String(describing: error), privacy: .public)")
        return error
    }

    private func seconds(since start: ContinuousClock.Instant, _ clock: ContinuousClock) -> Double {
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    // MARK: - Receipts

    /// Real token counts: the response's `usage` on 27; on 26.4 the model's token counter over
    /// instructions, prompt, schema and generated content; before that, an estimate.
    private func receipt<C: Generable>(
        for response: LanguageModelSession.Response<C>, instructions: String, prompt: String,
        schema: GenerationSchema, seconds: Double
    ) async -> BrainCallReceipt {
        if #available(iOS 27.0, macOS 27.0, *) {
            return BrainCallReceipt(
                inputTokens: response.usage.input.totalTokenCount,
                outputTokens: response.usage.output.totalTokenCount, wallSeconds: seconds)
        }
        if #available(iOS 26.4, macOS 26.4, *) {
            // VERIFY: compiled against the 27 SDK only; not run on a 26.4 device. Whether the
            // schema count matches what the session adds to the prompt is unconfirmed.
            do {
                let input =
                    try await model.tokenCount(for: Instructions(instructions))
                    + model.tokenCount(for: Prompt(prompt)) + model.tokenCount(for: schema)
                let output = try await model.tokenCount(for: Prompt(response.rawContent.jsonString))
                return BrainCallReceipt(inputTokens: input, outputTokens: output, wallSeconds: seconds)
            } catch {
                log.notice("token count unavailable: \(String(describing: error), privacy: .public)")
            }
        }
        let characters = instructions.count + prompt.count
        return BrainCallReceipt(
            inputTokens: characters / 4 + 400, outputTokens: response.rawContent.jsonString.count / 4,
            wallSeconds: seconds)
    }

    // MARK: - Errors

    private enum Failure {
        case contextExceeded(String)
        case brain(BrainError)
        /// The task was cancelled; rethrown as is so a stopped run stops instead of failing every call.
        case cancelled
    }

    /// Maps every error the framework can throw to a `BrainError`, so none escapes into the
    /// simulation's step. iOS 27 throws `LanguageModelError` and friends; iOS 26 (and apps
    /// built with Xcode 26) throws `LanguageModelSession.GenerationError`.
    private static func classify(_ error: any Error) -> Failure {
        if error is CancellationError {
            return .cancelled
        }
        if let error = error as? BrainError {
            return .brain(error)
        }
        if #available(iOS 27.0, macOS 27.0, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded(let context):
                    return .contextExceeded("\(context.tokenCount) of \(context.contextSize) tokens")
                case .guardrailViolation, .refusal:
                    return .brain(.refused(error.localizedDescription))
                case .rateLimited, .timeout:
                    return .brain(.unavailable(error.localizedDescription))
                case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide,
                    .unsupportedLanguageOrLocale:
                    return .brain(.malformed(error.localizedDescription))
                @unknown default:
                    return .brain(.malformed(error.localizedDescription))
                }
            }
            if let error = error as? SystemLanguageModel.Error {
                switch error {
                case .assetsUnavailable:
                    return .brain(.unavailable(error.localizedDescription))
                @unknown default:
                    return .brain(.unavailable(error.localizedDescription))
                }
            }
            if let error = error as? LanguageModelSession.Error {
                switch error {
                case .concurrentRequests, .transcriptMutationWhileResponding:
                    return .brain(.malformed(error.localizedDescription))
                @unknown default:
                    return .brain(.malformed(error.localizedDescription))
                }
            }
            if let error = error as? GeneratedContent.ParsingError {
                return .brain(.malformed("parsing: \(error.debugDescription)"))
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                return .contextExceeded(error.localizedDescription)
            case .guardrailViolation, .refusal:
                return .brain(.refused(error.localizedDescription))
            case .assetsUnavailable, .rateLimited:
                return .brain(.unavailable(error.localizedDescription))
            case .unsupportedGuide, .unsupportedLanguageOrLocale, .decodingFailure, .concurrentRequests:
                return .brain(.malformed(error.localizedDescription))
            @unknown default:
                return .brain(.malformed(error.localizedDescription))
            }
        }
        // Decoding the generated content into a mirror type, or anything else unforeseen.
        return .brain(.malformed(String(describing: error)))
    }
}
#endif
