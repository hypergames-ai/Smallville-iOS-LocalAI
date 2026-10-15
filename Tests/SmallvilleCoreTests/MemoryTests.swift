import Testing

@testable import SmallvilleCore

@Suite("Memory stream")
struct MemoryTests {
    @Test("retrieval prefers the relevant, recent, important memory")
    func retrievalScoring() {
        let embedder = HashingEmbedder()
        var stream = MemoryStream()
        let bookText = "Klaus read a book about gentrification in the library"
        let partyText = "Isabella is planning a Valentine's party at Hobbs Cafe"
        stream.append(
            kind: .observation, text: bookText, poignancy: 3, provenance: .observed, embedding: embedder.embed(bookText),
            at: SimTime(minutes: 0))
        stream.append(
            kind: .observation, text: partyText, poignancy: 8, provenance: .observed,
            embedding: embedder.embed(partyText), at: SimTime(minutes: 600))

        let hits = stream.retrieve(query: embedder.embed("party at the cafe"), now: SimTime(minutes: 700), limit: 1)
        #expect(hits.first?.text == partyText)
        #expect(hits.first?.lastAccessed == SimTime(minutes: 700), "retrieval touches lastAccessed")
    }

    @Test("storyline tags make knowledge a query")
    func storylineTags() {
        let embedder = HashingEmbedder()
        var stream = MemoryStream()
        let party = StorylineID("valentines-party")
        #expect(!stream.knows(party))
        stream.append(
            kind: .whisper, text: "a party", poignancy: 8, provenance: .whispered, storylines: [party],
            embedding: embedder.embed("a party"), at: SimTime(minutes: 0))
        #expect(stream.knows(party))
        #expect(stream.nodes(for: party).count == 1)
    }

    @Test("hashing embedder is deterministic and normalized")
    func hashingEmbedder() {
        let embedder = HashingEmbedder()
        let a = embedder.embed("coffee at the cafe")
        let b = embedder.embed("coffee at the cafe")
        #expect(a == b)
        #expect(abs(cosine(a, a) - 1) < 0.0001)
        #expect(cosine(a, embedder.embed("quantum chromodynamics lecture")) < 0.5)
    }
}
