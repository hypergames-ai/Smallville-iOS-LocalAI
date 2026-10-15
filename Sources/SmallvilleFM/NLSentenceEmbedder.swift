#if canImport(NaturalLanguage)
import Foundation
import NaturalLanguage
import SmallvilleCore

/// Sentence embeddings from Apple's NaturalLanguage framework for the relevance term of
/// retrieval on devices. Falls back to the hashing embedder when the model isn't available.
public struct NLSentenceEmbedder: Embedder {
    public let dimension: Int
    private let fallback: HashingEmbedder
    // NLEmbedding is an NSObject that is safe to query from any thread once loaded.
    nonisolated(unsafe) private let embedding: NLEmbedding?

    public init(language: NLLanguage = .english) {
        let embedding = NLEmbedding.sentenceEmbedding(for: language)
        let dimension = embedding?.dimension ?? 64
        self.embedding = embedding
        self.dimension = dimension
        self.fallback = HashingEmbedder(dimension: dimension)
    }

    public func embed(_ text: String) -> [Float] {
        guard let embedding, let vector = embedding.vector(for: text) else {
            return fallback.embed(text)
        }
        return vector.map { Float($0) }
    }
}
#endif
