import Foundation

/// What kind of memory a node is. Mirrors the original's event / thought / chat split.
public enum MemoryKind: String, Hashable, Sendable, Codable {
    case observation
    case chat
    case reflection
    case plan
    case whisper
}

/// Where a memory came from. This is what lets the storyline detector trace diffusion.
public enum Provenance: Hashable, Sendable, Codable {
    /// The agent perceived it directly.
    case observed
    /// Another agent conveyed it in a conversation.
    case told(by: AgentID, at: SimTime)
    /// Synthesized by reflection from other memory ids.
    case reflected(from: [Int])
    /// Planted by the player.
    case whispered
}

/// One entry in an agent's memory stream.
public struct MemoryNode: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public let kind: MemoryKind
    public let created: SimTime
    public var lastAccessed: SimTime
    public let text: String
    /// 1 (mundane) to 10 (life-changing), as in the paper.
    public var poignancy: Int
    public let provenance: Provenance
    public let storylines: Set<StorylineID>
    public let embedding: [Float]
}

/// Weights for the retrieval score. Defaults match the paper (all 1) with its 0.995 decay.
public struct RetrievalWeights: Sendable {
    public var recency: Double = 1
    public var importance: Double = 1
    public var relevance: Double = 1
    /// Per-hour decay applied to recency.
    public var decay: Double = 0.995

    public init() {}
}

/// An agent's append-only memory with the paper's recency + importance + relevance retrieval.
public struct MemoryStream: Sendable, Codable {
    public private(set) var nodes: [MemoryNode] = []
    /// Sum of poignancy appended since the last reflection; drives the reflection trigger.
    public private(set) var importanceSinceReflection = 0
    /// First node id appended after the last `markReflected()`: only nodes at or above it are
    /// part of `importanceSinceReflection`.
    private var reflectionWatermark = 0
    private var nextID = 0

    public init() {}

    @discardableResult
    public mutating func append(
        kind: MemoryKind, text: String, poignancy: Int, provenance: Provenance,
        storylines: Set<StorylineID> = [], embedding: [Float], at now: SimTime
    ) -> MemoryNode {
        let node = MemoryNode(
            id: nextID, kind: kind, created: now, lastAccessed: now, text: text,
            poignancy: max(1, min(10, poignancy)), provenance: provenance, storylines: storylines,
            embedding: embedding)
        nextID += 1
        nodes.append(node)
        importanceSinceReflection += node.poignancy
        return node
    }

    public mutating func markReflected() {
        importanceSinceReflection = 0
        reflectionWatermark = nextID
    }

    /// Replaces default scores with rated ones. A memory added since the last reflection moves
    /// the reflection trigger by the difference; an older one only changes its own score.
    public mutating func setPoignancy(_ updates: some Sequence<(Int, Int)>) {
        for (id, poignancy) in updates {
            guard let index = nodes.firstIndex(where: { $0.id == id }) else { continue }
            let rated = max(1, min(10, poignancy))
            if id >= reflectionWatermark {
                importanceSinceReflection += rated - nodes[index].poignancy
            }
            nodes[index].poignancy = rated
        }
    }

    public func knows(_ storyline: StorylineID) -> Bool {
        nodes.contains { $0.storylines.contains(storyline) }
    }

    public func nodes(for storyline: StorylineID) -> [MemoryNode] {
        nodes.filter { $0.storylines.contains(storyline) }
    }

    public func recent(_ count: Int) -> [MemoryNode] {
        Array(nodes.suffix(count))
    }

    /// The paper's retention rule: true if the same text was stored within the last `count` nodes.
    public func recentlyContains(_ text: String, within count: Int) -> Bool {
        nodes.suffix(count).contains { $0.text == text }
    }

    /// Top-`limit` nodes by normalized recency + importance + relevance. Touches `lastAccessed`
    /// on the returned nodes, as the paper does.
    public mutating func retrieve(
        query: [Float], now: SimTime, limit: Int, weights: RetrievalWeights = RetrievalWeights()
    ) -> [MemoryNode] {
        guard !nodes.isEmpty, limit > 0 else { return [] }

        let recency = nodes.map { node -> Double in
            let hours = Double(max(0, now.minutes - node.lastAccessed.minutes)) / 60
            return pow(weights.decay, hours)
        }
        let importance = nodes.map { Double($0.poignancy) / 10 }
        let relevance = nodes.map { Double(cosine($0.embedding, query)) }

        let r = minMaxNormalized(recency)
        let i = minMaxNormalized(importance)
        let v = minMaxNormalized(relevance)

        let scored = nodes.indices.map { index in
            (index, weights.recency * r[index] + weights.importance * i[index] + weights.relevance * v[index])
        }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(limit)

        var result: [MemoryNode] = []
        for (index, _) in top {
            nodes[index].lastAccessed = now
            result.append(nodes[index])
        }
        return result
    }
}

private func minMaxNormalized(_ values: [Double]) -> [Double] {
    guard let low = values.min(), let high = values.max(), high > low else {
        return values.map { _ in 0.5 }
    }
    return values.map { ($0 - low) / (high - low) }
}
