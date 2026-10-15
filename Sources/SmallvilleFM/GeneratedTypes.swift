#if canImport(FoundationModels)
import Foundation
import FoundationModels

// The shapes the model fills in. They mirror the core's plain types one-to-one; the mapping
// lives in FoundationModelsBrain. Descriptions count against the 3,000-token prompt budget,
// so keep them short.
//
// VERIFY: `@Guide` accepting more than one guide (`.minimumCount` and `.maximumCount` together)
// and `.range` on Int properties. Confirm with the apple-docs subagent on the iOS 27 SDK.

@Generable(description: "A plan for one day as a short chronological outline.")
struct GeneratedDayPlan {
    @Guide(description: "Hour the person wakes up", .range(5...10))
    var wakeHour: Int
    @Guide(description: "Four to eight entries in chronological order", .minimumCount(4), .maximumCount(8))
    var entries: [GeneratedDayPlanEntry]
}

@Generable
struct GeneratedDayPlanEntry {
    @Guide(description: "Hour of day", .range(0...23))
    var hour: Int
    @Guide(description: "What they do, under twelve words")
    var activity: String
}

@Generable(description: "What the person does during the coming hour.")
struct GeneratedHourPlan {
    @Guide(description: "One to three actions that together fill the hour", .minimumCount(1), .maximumCount(3))
    var actions: [GeneratedAction]
}

@Generable
struct GeneratedAction {
    @Guide(description: "Minute within the hour the action starts", .range(0...59))
    var startMinute: Int
    @Guide(description: "Length in minutes", .range(10...60))
    var durationMinutes: Int
    @Guide(description: "The activity in one short sentence")
    var activity: String
    // TODO: constrain to the known locations with DynamicGenerationSchema instead of a free string.
    @Guide(description: "Location id, copied exactly from the list in the prompt")
    var locationID: String
    @Guide(description: "A single emoji for the activity")
    var emoji: String
    @Guide(description: "Event subject, usually the person's name")
    var subject: String
    @Guide(description: "Event predicate, a verb phrase")
    var predicate: String
    @Guide(description: "Event object")
    var object: String
}

@Generable(description: "A short conversation between two residents and what it accomplished socially.")
struct GeneratedConversation {
    @Guide(description: "Two to six alternating turns", .minimumCount(2), .maximumCount(6))
    var turns: [GeneratedTurn]
    @Guide(description: "Every social act that happened, at most four", .maximumCount(4))
    var acts: [GeneratedSocialAct]
    @Guide(description: "Ids of storylines mentioned, copied exactly from the prompt, or empty")
    var conveyedStorylineIDs: [String]
    @Guide(description: "One-sentence memory of the chat from the first speaker's point of view")
    var initiatorSummary: String
    @Guide(description: "One-sentence memory of the chat from the second speaker's point of view")
    var partnerSummary: String
}

@Generable
struct GeneratedTurn {
    @Guide(description: "Speaker's name exactly as given")
    var speaker: String
    @Guide(description: "What they say, under twenty-five words")
    var text: String
}

@Generable
struct GeneratedSocialAct {
    @Guide(
        description: "Kind of act",
        .anyOf(["invite", "accept", "decline", "inform", "ask", "gossip", "plan", "disagree"]))
    var kind: String
    @Guide(description: "Name of the person performing the act")
    var from: String
    @Guide(description: "Name of the person it is directed at")
    var to: String
    @Guide(description: "Topic in a few words")
    var topic: String
    @Guide(description: "Storyline id it concerns, copied from the prompt, or empty")
    var storylineID: String
}

@Generable(description: "High-level insights drawn from recent memories.")
struct GeneratedReflections {
    @Guide(description: "One to three insights", .minimumCount(1), .maximumCount(3))
    var insights: [GeneratedReflection]
}

@Generable
struct GeneratedReflection {
    @Guide(description: "The insight in one sentence")
    var insight: String
    @Guide(description: "Memory ids from the prompt that support it", .maximumCount(5))
    var evidence: [Int]
}

@Generable(description: "How memorable each memory is.")
struct GeneratedRatings {
    @Guide(description: "One rating from 1 (mundane) to 10 (life-changing) per memory, in order")
    var ratings: [Int]
}
#endif
