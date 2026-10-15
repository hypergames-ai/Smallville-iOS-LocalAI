#if canImport(FoundationModels)
import Foundation
import FoundationModels
import Testing

@testable import SmallvilleCore
@testable import SmallvilleFM

/// Contexts and schema inspection for the adapter tests. Nothing here touches the model.
enum Fixtures {
    static let world = WorldMap.smallvilleSubset()

    static let party = Storyline(
        id: StorylineID("valentines-party"), title: "Valentine's Day party at Hobbs Cafe",
        seedText: "Isabella is throwing a party.", seededIn: AgentProfile.isabella.id,
        seededAt: SimTime(minutes: 7 * 60), targetLocation: WorldMap.hobbsCafe,
        eventTime: SimTime(minutes: 24 * 60 + 17 * 60))

    static func context(
        _ profile: AgentProfile = .klaus, memories: [String] = [], knownLocations: [Location]? = nil,
        storylines: [Storyline] = []
    ) throws -> AgentContext {
        let embedder = HashingEmbedder()
        var stream = MemoryStream()
        for text in memories {
            stream.append(
                kind: .observation, text: text, poignancy: 3, provenance: .observed, embedding: embedder.embed(text),
                at: SimTime(minutes: 7 * 60))
        }
        let here = try #require(world.location(profile.home))
        return AgentContext(
            profile: profile, now: SimTime(minutes: 9 * 60), location: here, relevantMemories: stream.nodes,
            knownLocations: knownLocations ?? Array(world.allLocations.prefix(4)), activeStorylines: storylines,
            dayPlan: nil)
    }

    /// The JSON Schema the model is given, as nested dictionaries.
    static func json(_ schema: GenerationSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The schema node for `property` wherever it is defined, with a `$ref` followed. Accepts
    /// `$defs` or `definitions`, so the tests do not depend on one encoder's layout.
    static func node(for property: String, in schema: GenerationSchema) throws -> [String: Any] {
        let root = try json(schema)
        let definitions = (root["$defs"] ?? root["definitions"]) as? [String: Any] ?? [:]
        func resolve(_ node: [String: Any]) -> [String: Any] {
            guard let reference = node["$ref"] as? String,
                let name = reference.split(separator: "/").last,
                let target = definitions[String(name)] as? [String: Any]
            else { return node }
            return target
        }
        for candidate in [root] + definitions.values.compactMap({ $0 as? [String: Any] }) {
            if let properties = resolve(candidate)["properties"] as? [String: Any],
                let target = properties[property] as? [String: Any]
            {
                var resolved = resolve(target)
                if let items = resolved["items"] as? [String: Any] {
                    resolved.merge(resolve(items)) { kept, _ in kept }
                }
                return resolved
            }
        }
        Issue.record("no property \(property)")
        return [:]
    }

    /// The string choices offered for `property`, written either as `enum` or as `anyOf` consts.
    static func choices(for property: String, in schema: GenerationSchema) throws -> [String] {
        let node = try node(for: property, in: schema)
        if let values = node["enum"] as? [String] {
            return values
        }
        if let options = node["anyOf"] as? [[String: Any]] {
            return options.compactMap { $0["const"] as? String ?? ($0["enum"] as? [String])?.first }
        }
        Issue.record("no choices for \(property)")
        return []
    }

    /// Decodes model output written by hand, the way the brain decodes real output.
    static func decode<T: Generable>(_ type: T.Type, _ json: String) throws -> T {
        try T(GeneratedContent(json: json))
    }
}
#endif
