import Foundation

/// Everything the brain gets to see when making a decision for one agent. Built by the
/// simulation; deliberately small so prompts stay under budget.
public struct AgentContext: Sendable {
    public var profile: AgentProfile
    public var now: SimTime
    public var location: Location
    public var relevantMemories: [MemoryNode]
    public var knownLocations: [Location]
    /// Storylines this agent has at least one memory about, nearest event first, capped by
    /// `Simulation.Configuration.maxStorylinesInContext`.
    public var activeStorylines: [Storyline]
    public var dayPlan: DayPlan?
    /// The day-plan entry in force this hour: the task the hour plan decomposes.
    public var currentEntry: DayPlanEntry?

    public init(
        profile: AgentProfile, now: SimTime, location: Location, relevantMemories: [MemoryNode],
        knownLocations: [Location], activeStorylines: [Storyline], dayPlan: DayPlan?,
        currentEntry: DayPlanEntry? = nil
    ) {
        self.profile = profile
        self.now = now
        self.location = location
        self.relevantMemories = relevantMemories
        self.knownLocations = knownLocations
        self.activeStorylines = activeStorylines
        self.dayPlan = dayPlan
        self.currentEntry = currentEntry
    }
}

/// One line of a day's outline.
public struct DayPlanEntry: Hashable, Sendable, Codable {
    public var hour: Int
    public var activity: String

    public init(hour: Int, activity: String) {
        self.hour = hour
        self.activity = activity
    }
}

/// The coarse plan an agent makes when it wakes up.
public struct DayPlan: Hashable, Sendable, Codable {
    public var wakeHour: Int
    public var entries: [DayPlanEntry]

    public init(wakeHour: Int, entries: [DayPlanEntry]) {
        self.wakeHour = wakeHour
        self.entries = entries
    }

    /// The entry in force at `hour`: the latest one that starts at or before it.
    public func entry(at hour: Int) -> DayPlanEntry? {
        entries.filter { $0.hour <= hour }.max { $0.hour < $1.hour }
    }
}

/// (subject, predicate, object), the original's representation of an event in the world.
public struct EventTriple: Hashable, Sendable, Codable {
    public var subject: String
    public var predicate: String
    public var object: String

    public init(subject: String, predicate: String, object: String) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }
}

/// One concrete thing an agent does during an hour, with where it does it.
public struct PlannedAction: Hashable, Sendable, Codable {
    public var startMinute: Int
    public var durationMinutes: Int
    public var activity: String
    public var location: LocationID
    public var emoji: String
    public var event: EventTriple

    public init(
        startMinute: Int, durationMinutes: Int, activity: String, location: LocationID, emoji: String,
        event: EventTriple
    ) {
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.activity = activity
        self.location = location
        self.emoji = emoji
        self.event = event
    }
}

/// The 1–3 actions that fill one hour. Replaces the original's eight-call decomposition chain.
public struct HourPlan: Hashable, Sendable, Codable {
    public var hour: Int
    public var actions: [PlannedAction]

    public init(hour: Int, actions: [PlannedAction]) {
        self.hour = hour
        self.actions = actions
    }

    public func action(atMinute minute: Int) -> PlannedAction? {
        actions.last { $0.startMinute <= minute }
    }

    /// The largest number of actions an hour is allowed to hold.
    public static let maxActions = 3

    /// Makes the plan safe to execute: starts clamped to the hour and snapped down to the tick
    /// grid (the simulation only samples minutes 0, 10, ..., 50), sorted, duplicates at the same
    /// start dropped, the first action pulled to minute 0, durations set to the gap to the next
    /// action (the last runs to the end of the hour), and at most `maxActions` kept.
    public func normalized(hour: Int) -> HourPlan {
        guard !actions.isEmpty else { return HourPlan(hour: hour, actions: []) }
        let tick = SimTime.minutesPerTick
        let clamped = actions.enumerated().map { offset, action -> (Int, PlannedAction) in
            var action = action
            action.startMinute = max(0, min(59, action.startMinute)) / tick * tick
            return (offset, action)
        }
        let sorted = clamped.sorted {
            $0.1.startMinute == $1.1.startMinute ? $0.0 < $1.0 : $0.1.startMinute < $1.1.startMinute
        }
        var kept: [PlannedAction] = []
        for (_, action) in sorted where kept.last?.startMinute != action.startMinute {
            kept.append(action)
            if kept.count == Self.maxActions { break }
        }
        kept[0].startMinute = 0
        for index in kept.indices {
            let end = index + 1 < kept.count ? kept[index + 1].startMinute : 60
            kept[index].durationMinutes = end - kept[index].startMinute
        }
        return HourPlan(hour: hour, actions: kept)
    }
}

/// One utterance.
public struct ConversationTurn: Hashable, Sendable, Codable {
    public var speaker: AgentID
    public var text: String

    public init(speaker: AgentID, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

/// A whole conversation generated in one call, plus what it accomplished.
public struct Conversation: Hashable, Sendable, Codable {
    public var initiator: AgentID
    public var partner: AgentID
    public var turns: [ConversationTurn]
    public var acts: [SocialAct]
    /// Storylines that were mentioned, so the listener's memory can be tagged.
    public var conveyedStorylines: [StorylineID]
    public var initiatorSummary: String
    public var partnerSummary: String

    public init(
        initiator: AgentID, partner: AgentID, turns: [ConversationTurn], acts: [SocialAct],
        conveyedStorylines: [StorylineID], initiatorSummary: String, partnerSummary: String
    ) {
        self.initiator = initiator
        self.partner = partner
        self.turns = turns
        self.acts = acts
        self.conveyedStorylines = conveyedStorylines
        self.initiatorSummary = initiatorSummary
        self.partnerSummary = partnerSummary
    }
}

/// Both sides of a conversation, as the brain sees them.
public struct ConversationRequest: Sendable {
    public var initiator: AgentContext
    public var partner: AgentContext
    public var maxTurns: Int

    public init(initiator: AgentContext, partner: AgentContext, maxTurns: Int) {
        self.initiator = initiator
        self.partner = partner
        self.maxTurns = maxTurns
    }
}

/// A higher-level thought synthesized from memories.
public struct Reflection: Hashable, Sendable, Codable {
    public var insight: String
    /// Ids of the memories that support it. The core drops ids the agent does not have, and
    /// drops the whole insight if none remain.
    public var evidence: [Int]

    public init(insight: String, evidence: [Int]) {
        self.insight = insight
        self.evidence = evidence
    }
}

/// What one brain call cost. The simulation records it; the budget judges it.
public struct BrainCallReceipt: Hashable, Sendable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var wallSeconds: Double

    public init(inputTokens: Int, outputTokens: Int, wallSeconds: Double) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.wallSeconds = wallSeconds
    }
}

/// A brain's answer together with its receipt.
public struct BrainResponse<Value: Sendable>: Sendable {
    public var value: Value
    public var receipt: BrainCallReceipt

    public init(value: Value, receipt: BrainCallReceipt) {
        self.value = value
        self.receipt = receipt
    }
}

/// The only errors a brain may throw. The simulation skips the decision and moves on.
public enum BrainError: Error, Sendable {
    /// The model is not available on this device or in this state.
    case unavailable(String)
    /// A guardrail or refusal; the decision is dropped, not retried.
    case refused(String)
    /// Output could not be mapped into the expected shape.
    case malformed(String)
}

/// The five decisions the simulation asks for. Everything else is rules in the core.
public protocol AgentBrain: Sendable {
    func planDay(_ context: AgentContext) async throws -> BrainResponse<DayPlan>
    func planHour(_ context: AgentContext, dayPlan: DayPlan) async throws -> BrainResponse<HourPlan>
    func converse(_ request: ConversationRequest) async throws -> BrainResponse<Conversation>
    func reflect(_ context: AgentContext) async throws -> BrainResponse<[Reflection]>
    func ratePoignancy(_ texts: [String], for profile: AgentProfile) async throws -> BrainResponse<[Int]>
}
