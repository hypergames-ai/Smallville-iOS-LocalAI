#if canImport(FoundationModels)
import Foundation
import SmallvilleCore

/// Pure conversions between the core's types and what the model sees and fills in: the choice
/// lists for `DynamicSchemas`, and generated mirrors back into core values. No model is
/// involved, so `SmallvilleFMTests` exercises all of it with hand-built content.
@available(iOS 26.0, macOS 26.0, *)
enum Mapping {
    /// The location ids an hour plan may use: the agent's known places, or where it is now if
    /// it knows none (a choice list must never be empty).
    static func locationIDs(for context: AgentContext) -> [String] {
        let known = context.knownLocations.map(\.id.rawValue)
        return known.isEmpty ? [context.location.id.rawValue] : known
    }

    /// Storylines either participant knows about, deduplicated in order.
    static func storylineIDs(for request: ConversationRequest) -> [String] {
        var ids: [String] = []
        for storyline in request.initiator.activeStorylines + request.partner.activeStorylines
        where !ids.contains(storyline.id.rawValue) {
            ids.append(storyline.id.rawValue)
        }
        return ids
    }

    /// The notes as generated; a blank `currently` keeps the previous status.
    static func identityRevision(_ generated: GeneratedIdentityRevision, previous: String) -> IdentityRevision {
        let currently = generated.currently.trimmingCharacters(in: .whitespacesAndNewlines)
        return IdentityRevision(
            planNote: generated.planNote, thoughtNote: generated.thoughtNote,
            currently: currently.isEmpty ? previous : currently)
    }

    /// The outline as generated, entry by entry.
    static func dayPlan(_ generated: GeneratedDayPlan) -> DayPlan {
        DayPlan(
            wakeHour: generated.wakeHour,
            entries: generated.entries.map { DayPlanEntry(hour: $0.hour, activity: $0.activity) })
    }

    /// The plan as generated; the simulation normalizes timing, emoji and locations.
    static func hourPlan(_ generated: GeneratedHourPlan, hour: Int) -> HourPlan {
        let actions = generated.actions.map { action in
            PlannedAction(
                startMinute: action.startMinute, durationMinutes: action.durationMinutes, activity: action.activity,
                location: LocationID(action.locationID), emoji: action.emoji,
                event: EventTriple(subject: action.subject, predicate: action.predicate, object: action.object))
        }
        return HourPlan(hour: hour, actions: actions)
    }

    /// Names become ids (the schema allows only the two participants' names; anything else
    /// falls back to the initiator), `none` storylines become nil, unknown act kinds are
    /// dropped, and conveyed storylines are deduplicated.
    static func conversation(
        _ generated: GeneratedConversation, initiator a: AgentProfile, partner b: AgentProfile
    ) -> Conversation {
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
        return Conversation(
            initiator: a.id, partner: b.id, turns: turns, acts: acts, conveyedStorylines: conveyed,
            initiatorSummary: generated.initiatorSummary, partnerSummary: generated.partnerSummary)
    }

    /// Evidence is limited to memory ids that were in the prompt.
    static func reflections(_ generated: GeneratedReflections, known: Set<Int>) -> [Reflection] {
        generated.insights.map {
            Reflection(insight: $0.insight, evidence: $0.evidence.filter { known.contains($0) })
        }
    }

    /// Exactly `count` ratings in 1...10: clamped, padded with 3 if short, truncated if long.
    static func ratings(_ generated: GeneratedRatings, count: Int) -> [Int] {
        var ratings = generated.ratings.map { max(1, min(10, $0)) }
        if ratings.count < count {
            ratings += Array(repeating: 3, count: count - ratings.count)
        }
        return Array(ratings.prefix(count))
    }
}
#endif
