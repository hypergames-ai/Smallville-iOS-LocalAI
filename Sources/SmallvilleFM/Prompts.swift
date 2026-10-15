#if canImport(FoundationModels)
import Foundation
import SmallvilleCore

/// Builds the text the model sees. Everything stable about an agent goes in `instructions`;
/// everything that changes goes at the end of the prompt. Budget: the whole thing must fit in
/// 3,000 tokens with the schema and the response, so these are terse by design. `memoryLimit`
/// caps retrieved memories per agent; the brain halves it to retry a context overflow.
enum Prompts {
    /// Memories per agent in a prompt unless a retry asks for fewer.
    static let defaultMemoryLimit = 8

    static func instructions(for profile: AgentProfile) -> String {
        """
        You are simulating \(profile.name), \(profile.age), \(profile.occupation), in the small town of Smallville.
        Innate traits: \(profile.innateTraits).
        Lifestyle: \(profile.lifestyle).
        Currently: \(profile.currently)
        Stay in character. Be concrete and brief. Use only locations and people named in the prompt.
        """
    }

    static func dayPlan(_ context: AgentContext, memoryLimit: Int = defaultMemoryLimit) -> String {
        """
        It is \(context.now). Write \(context.profile.name)'s plan for today as an hour-by-hour outline.
        \(memoryBlock(context, limit: memoryLimit))
        """
    }

    static func hourPlan(_ context: AgentContext, dayPlan: DayPlan, memoryLimit: Int = defaultMemoryLimit) -> String {
        let outline = dayPlan.entries.map { "\($0.hour):00 \($0.activity)" }.joined(separator: "; ")
        let task = context.currentEntry?.activity ?? "whatever fits the outline"
        return """
            It is \(context.now). \(context.profile.name) is at \(context.location.name).
            Today's outline: \(outline)
            This hour's task: \(task)
            \(locationBlock(context))
            \(storylineBlock(context))
            \(memoryBlock(context, limit: memoryLimit))
            Decide what \(context.profile.name) does for the next hour.
            """
    }

    static func conversation(_ request: ConversationRequest, memoryLimit: Int = 5) -> String {
        let a = request.initiator
        let b = request.partner
        let relationship = a.profile.relationships[b.profile.id] ?? "an acquaintance"
        let storylines = (a.activeStorylines + b.activeStorylines).map { "\($0.id.rawValue): \($0.title)" }
        let storylineText = storylines.isEmpty ? "none" : Set(storylines).sorted().joined(separator: "; ")
        return """
            It is \(a.now). \(a.profile.name) runs into \(b.profile.name) (\(relationship)) at \(a.location.name).
            \(b.profile.name) is \(b.profile.age), \(b.profile.occupation); traits: \(b.profile.innateTraits).
            Storylines in play: \(storylineText)
            What \(a.profile.name) remembers:
            \(lines(a.relevantMemories.prefix(memoryLimit)))
            What \(b.profile.name) remembers:
            \(lines(b.relevantMemories.prefix(max(0, memoryLimit - 1))))
            Write the conversation (at most \(request.maxTurns) turns), then list the social acts it contained.
            Use the full names \(a.profile.name) and \(b.profile.name). Use storyline ids as listed, or none.
            """
    }

    static func reflection(_ context: AgentContext, memoryLimit: Int = defaultMemoryLimit) -> String {
        """
        It is \(context.now). Here are \(context.profile.name)'s recent memories, with ids:
        \(lines(context.relevantMemories.prefix(memoryLimit), withIDs: true))
        What are one to three high-level insights \(context.profile.name) could draw? Cite memory ids.
        """
    }

    static func poignancy(_ texts: [String], for profile: AgentProfile) -> String {
        let numbered = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return """
            Rate how memorable each event is for \(profile.name) from 1 (brushing teeth) to 10 (a breakup or a big party).
            \(numbered)
            """
    }

    // MARK: - Blocks

    private static func locationBlock(_ context: AgentContext) -> String {
        // The same fallback as Mapping.locationIDs, so the prompt lists exactly the schema's choices.
        let known = context.knownLocations.isEmpty ? [context.location] : context.knownLocations
        let places = known.map { "\($0.id.rawValue) (\($0.name))" }.joined(separator: ", ")
        return "Known locations: \(places)"
    }

    private static func storylineBlock(_ context: AgentContext) -> String {
        guard !context.activeStorylines.isEmpty else { return "" }
        let items = context.activeStorylines.map { storyline -> String in
            var line = "\(storyline.id.rawValue): \(storyline.title)"
            if let time = storyline.eventTime, let location = storyline.targetLocation {
                line += " at \(location.rawValue) on \(time)"
            }
            return line
        }
        return "Things \(context.profile.name) knows about: " + items.joined(separator: "; ")
    }

    private static func memoryBlock(_ context: AgentContext, limit: Int) -> String {
        guard !context.relevantMemories.isEmpty, limit > 0 else { return "" }
        return "Relevant memories:\n" + lines(context.relevantMemories.prefix(limit))
    }

    private static func lines(_ memories: some Sequence<MemoryNode>, withIDs: Bool = false) -> String {
        memories.map { withIDs ? "[\($0.id)] \($0.text)" : "- \($0.text)" }.joined(separator: "\n")
    }
}
#endif
