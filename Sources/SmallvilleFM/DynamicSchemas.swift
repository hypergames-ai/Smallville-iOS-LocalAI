#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SmallvilleCore

/// Runtime schemas for the calls whose answers must be one of a known set: locations,
/// storylines and speakers. Property names match the `@Generable` mirrors in
/// `GeneratedTypes.swift`, so the output decodes into them; descriptions match their `@Guide`s.
@available(iOS 26.0, macOS 26.0, *)
enum DynamicSchemas {
    /// The storyline choice that means "no storyline"; dropped when mapping.
    static let noStoryline = "none"

    /// The smallest `maximumElements` an optional array may have; `conveyedStorylineIDs` is the
    /// only array that could otherwise shrink to one (`turns` and `acts` are safe by construction).
    /// On macOS 27 (AFM 3 Core) an array bounded 0...1 fails every call with `LanguageModelError`
    /// -1 (ModelManagerError 1032); 0...2, 1...1 and 2...2 work.
    // VERIFY: probed on macOS 27 / AFM 3 Core only, not documented; re-probe 0...1 on an iOS 27
    // device and later model builds before relaxing this.
    static let minimumArrayCeiling = 2

    /// `GeneratedHourPlan` with `locationID` limited to `locationIDs`, which must not be empty.
    static func hourPlan(locationIDs: [String]) throws -> GenerationSchema {
        let action = DynamicGenerationSchema(
            name: "GeneratedAction",
            properties: [
                property("startMinute", "Minute within the hour the action starts", int(0...59)),
                property("durationMinutes", "Length in minutes", int(10...60)),
                property("activity", "The activity in one short sentence", string),
                property("locationID", "Location id", choice("LocationID", locationIDs)),
                property("emoji", "A single emoji for the activity", string),
                property("subject", "Event subject, usually the person's name", string),
                property("predicate", "Event predicate, a verb phrase", string),
                property("object", "Event object", string),
            ])
        let root = DynamicGenerationSchema(
            name: "GeneratedHourPlan", description: "What the person does during the coming hour.",
            properties: [
                property(
                    "actions", "One to three actions that together fill the hour",
                    DynamicGenerationSchema(arrayOf: action, minimumElements: 1, maximumElements: 3))
            ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// `GeneratedConversation` with speakers limited to `names` and storylines to
    /// `storylineIDs` plus `noStoryline`.
    static func conversation(names: [String], storylineIDs: [String], maxTurns: Int) throws -> GenerationSchema {
        let storylines = storylineIDs + [noStoryline]
        let turn = DynamicGenerationSchema(
            name: "GeneratedTurn",
            properties: [
                property("speaker", "Speaker's full name", choice("Speaker", names)),
                property("text", "What they say, under twenty-five words", string),
            ])
        let act = DynamicGenerationSchema(
            name: "GeneratedSocialAct",
            properties: [
                property("kind", "Kind of act", choice("SocialActKind", SocialActKind.allCases.map(\.rawValue))),
                property("from", "Name of the person performing the act", choice("From", names)),
                property("to", "Name of the person it is directed at", choice("To", names)),
                property("topic", "Topic in a few words", string),
                property("storylineID", "Storyline it concerns, or none", choice("ActStoryline", storylines)),
            ])
        let root = DynamicGenerationSchema(
            name: "GeneratedConversation",
            description: "A short conversation between two residents and what it accomplished socially.",
            properties: [
                property(
                    "turns", "Alternating turns",
                    DynamicGenerationSchema(
                        arrayOf: turn, minimumElements: min(2, max(1, maxTurns)), maximumElements: max(1, maxTurns))),
                property(
                    "acts", "Every social act that happened, at most four",
                    DynamicGenerationSchema(arrayOf: act, minimumElements: 0, maximumElements: 4)),
                property(
                    "conveyedStorylineIDs", "Storylines mentioned, or none",
                    DynamicGenerationSchema(
                        arrayOf: choice("ConveyedStoryline", storylines), minimumElements: 0,
                        maximumElements: max(minimumArrayCeiling, storylines.count))),
                property(
                    "initiatorSummary", "One-sentence memory of the chat from the first speaker's point of view",
                    string),
                property(
                    "partnerSummary", "One-sentence memory of the chat from the second speaker's point of view",
                    string),
            ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    // MARK: - Pieces

    private static var string: DynamicGenerationSchema {
        DynamicGenerationSchema(type: String.self)
    }

    private static func int(_ range: ClosedRange<Int>) -> DynamicGenerationSchema {
        DynamicGenerationSchema(type: Int.self, guides: [.range(range)])
    }

    /// One of `values`, deduplicated in order. An empty list would throw `emptyTypeChoices`;
    /// callers always pass at least one value.
    private static func choice(_ name: String, _ values: [String]) -> DynamicGenerationSchema {
        var seen = Set<String>()
        return DynamicGenerationSchema(name: name, anyOf: values.filter { seen.insert($0).inserted })
    }

    private static func property(
        _ name: String, _ description: String, _ schema: DynamicGenerationSchema
    ) -> DynamicGenerationSchema.Property {
        DynamicGenerationSchema.Property(name: name, description: description, schema: schema)
    }
}
#endif
