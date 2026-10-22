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
    /// The full text of every call (instructions, prompt, schema, response), category "trace".
    private let trace = Logger(subsystem: "smallville", category: "trace")
    private var traceCount = 0

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    // MARK: - AgentBrain

    public func reviseIdentity(_ context: AgentContext) async throws -> BrainResponse<IdentityRevision> {
        let (generated, receipt) = try await respond(
            .reviseIdentity, for: context.profile, decoding: GeneratedIdentityRevision.self
        ) { Prompts.identityRevision(context, memoryLimit: $0) }
        return BrainResponse(
            value: Mapping.identityRevision(generated, previous: context.profile.currently), receipt: receipt)
    }

    public func planDay(_ context: AgentContext) async throws -> BrainResponse<DayPlan> {
        let (generated, receipt) = try await respond(
            .planDay, for: context.profile, decoding: GeneratedDayPlan.self
        ) { Prompts.dayPlan(context, memoryLimit: $0) }
        return BrainResponse(value: Mapping.dayPlan(generated), receipt: receipt)
    }

    public func planHour(_ context: AgentContext, dayPlan: DayPlan) async throws -> BrainResponse<HourPlan> {
        let schema = try makeSchema { try DynamicSchemas.hourPlan(locationIDs: Mapping.locationIDs(for: context)) }
        let (generated, receipt) = try await respond(
            .planHour, for: context.profile, schema: schema, decoding: GeneratedHourPlan.self
        ) { Prompts.hourPlan(context, dayPlan: dayPlan, memoryLimit: $0) }
        return BrainResponse(value: Mapping.hourPlan(generated, hour: context.now.hour), receipt: receipt)
    }

    public func converse(_ request: ConversationRequest) async throws -> BrainResponse<Conversation> {
        let a = request.initiator.profile
        let b = request.partner.profile
        let schema = try makeSchema {
            try DynamicSchemas.conversation(
                names: [a.name, b.name], storylineIDs: Mapping.storylineIDs(for: request), maxTurns: request.maxTurns)
        }
        let (generated, receipt) = try await respond(
            .converse, for: a, schema: schema, decoding: GeneratedConversation.self, memoryLimit: 5
        ) { Prompts.conversation(request, memoryLimit: $0) }
        return BrainResponse(value: Mapping.conversation(generated, initiator: a, partner: b), receipt: receipt)
    }

    public func reflect(_ context: AgentContext) async throws -> BrainResponse<[Reflection]> {
        let (generated, receipt) = try await respond(
            .reflect, for: context.profile, decoding: GeneratedReflections.self
        ) { Prompts.reflection(context, memoryLimit: $0) }
        let known = Set(context.relevantMemories.map(\.id))
        return BrainResponse(value: Mapping.reflections(generated, known: known), receipt: receipt)
    }

    public func ratePoignancy(_ texts: [String], for profile: AgentProfile) async throws -> BrainResponse<[Int]> {
        guard !texts.isEmpty else {
            return BrainResponse(
                value: [], receipt: BrainCallReceipt(inputTokens: 0, outputTokens: 0, wallSeconds: 0))
        }
        let (generated, receipt) = try await respond(
            .ratePoignancy, for: profile, decoding: GeneratedRatings.self, memoryLimit: 0
        ) { _ in Prompts.poignancy(texts, for: profile) }
        return BrainResponse(value: Mapping.ratings(generated, count: texts.count), receipt: receipt)
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
            traceCount += 1
            let call = "#\(traceCount) \(kind.rawValue) \(profile.id.rawValue)"
            traceSection("\(call) INSTRUCTIONS", instructions)
            traceSection("\(call) PROMPT", text)
            traceSection("\(call) SCHEMA", Self.json(schema ?? Content.generationSchema))
            let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let content: Content
                let receipt: BrainCallReceipt
                let raw: GeneratedContent
                if let schema {
                    let response = try await session.respond(to: text, schema: schema)
                    content = try Content(response.content)
                    raw = response.rawContent
                    receipt = await self.receipt(
                        for: response, instructions: instructions, prompt: text, schema: schema,
                        seconds: seconds(since: start, clock))
                } else {
                    let response = try await session.respond(to: text, generating: type)
                    content = response.content
                    raw = response.rawContent
                    receipt = await self.receipt(
                        for: response, instructions: instructions, prompt: text, schema: Content.generationSchema,
                        seconds: seconds(since: start, clock))
                }
                traceSection(
                    "\(call) RESPONSE (in \(receipt.inputTokens) out \(receipt.outputTokens) tokens)", raw.jsonString)
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

    // MARK: - Trace

    /// Logs `text` under `header`, split on line boundaries into pieces of at most 800 bytes.
    /// Both are autoclosures so nothing is built (schema JSON included) unless the "trace"
    /// category is capturing debug messages, e.g. under Xcode or `log stream --level debug`.
    // The unified log truncates long messages; 800-byte pieces come through whole on an iPhone
    // (checked on device), though the exact limit was not measured.
    private func traceSection(_ header: @autoclosure () -> String, _ text: @autoclosure () -> String) {
        guard trace.isEnabled(type: .debug) else { return }
        let header = header()
        let text = text()
        var pieces: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(line)
            while line.utf8.count > 800 {
                let head = String(line.prefix(700))
                pieces.append(head)
                line = String(line.dropFirst(head.count))
            }
            if !current.isEmpty, current.utf8.count + line.utf8.count + 1 > 800 {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        pieces.append(current)
        for (index, piece) in pieces.enumerated() {
            trace.debug("\(header, privacy: .public) [\(index + 1)/\(pieces.count)]\n\(piece, privacy: .public)")
        }
    }

    /// The schema as the JSON the framework encodes it to, keys sorted.
    private static func json(_ schema: GenerationSchema) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schema) else { return schema.debugDescription }
        return String(decoding: data, as: UTF8.self)
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
