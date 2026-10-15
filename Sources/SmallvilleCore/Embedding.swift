import Foundation

/// Turns text into a vector for the relevance term of memory retrieval.
public protocol Embedder: Sendable {
    var dimension: Int { get }
    func embed(_ text: String) -> [Float]
}

/// Deterministic bag-of-words embedding (feature hashing). Good enough for tests and for
/// running on Linux; devices use the NaturalLanguage embedder from the FM target.
public struct HashingEmbedder: Embedder {
    public let dimension: Int

    public init(dimension: Int = 64) {
        self.dimension = dimension
    }

    public func embed(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for word in words where word.count > 2 {
            let hash = fnv1a(word)
            let index = Int(hash % UInt64(dimension))
            vector[index] += (hash & 1 == 0) ? 1 : -1
        }
        return normalized(vector)
    }
}

/// FNV-1a: stable across processes, unlike `Hasher`, which is randomly seeded.
func fnv1a<S: StringProtocol>(_ text: S) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return hash
}

func normalized(_ vector: [Float]) -> [Float] {
    let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
    guard norm > 0 else { return vector }
    return vector.map { $0 / norm }
}

/// Cosine similarity in [-1, 1]; 0 for mismatched or empty vectors.
public func cosine(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for index in a.indices {
        dot += a[index] * b[index]
        normA += a[index] * a[index]
        normB += b[index] * b[index]
    }
    let denominator = normA.squareRoot() * normB.squareRoot()
    guard denominator > 0 else { return 0 }
    return dot / denominator
}
