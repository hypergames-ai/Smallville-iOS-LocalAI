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
            kind: .observation, text: bookText, poignancy: 3, provenance: .observed,
            embedding: embedder.embed(bookText),
            at: SimTime(minutes: 0))
        stream.append(
            kind: .observation, text: partyText, poignancy: 8, provenance: .observed,
            embedding: embedder.embed(partyText), at: SimTime(minutes: 600))

        let hits = stream.retrieve(query: embedder.embed("party at the cafe"), now: SimTime(minutes: 700), limit: 1)
        #expect(hits.first?.text == partyText)
        #expect(hits.first?.lastAccessed == SimTime(minutes: 700), "retrieval touches lastAccessed")
    }

    /// Two nodes that differ in exactly one retrieval term.
    private static func pair(
        poignancy: (Int, Int) = (5, 5), accessed: (Int, Int) = (0, 0),
        texts: (String, String) = ("same words", "same words")
    ) -> MemoryStream {
        let embedder = HashingEmbedder()
        var stream = MemoryStream()
        stream.append(
            kind: .observation, text: texts.0, poignancy: poignancy.0, provenance: .observed,
            embedding: embedder.embed(texts.0), at: SimTime(minutes: accessed.0))
        stream.append(
            kind: .observation, text: texts.1, poignancy: poignancy.1, provenance: .observed,
            embedding: embedder.embed(texts.1), at: SimTime(minutes: accessed.1))
        return stream
    }

    @Test("recency alone: the more recently accessed memory wins")
    func recencyTerm() {
        var stream = Self.pair(accessed: (0, 600))
        let hits = stream.retrieve(query: HashingEmbedder().embed("unrelated"), now: SimTime(minutes: 700), limit: 1)
        #expect(hits.first?.id == 1)
    }

    @Test("importance alone: the more poignant memory wins")
    func importanceTerm() {
        var stream = Self.pair(poignancy: (9, 3))
        let hits = stream.retrieve(query: HashingEmbedder().embed("unrelated"), now: SimTime(minutes: 100), limit: 1)
        #expect(hits.first?.id == 0)
    }

    @Test("relevance alone: the closer text wins")
    func relevanceTerm() {
        var stream = Self.pair(texts: ("coffee at the cafe counter", "physics lecture notes"))
        let hits = stream.retrieve(query: HashingEmbedder().embed("cafe coffee"), now: SimTime(minutes: 100), limit: 1)
        #expect(hits.first?.id == 0)
    }

    @Test("retention: the same text is not stored twice in a row")
    func retention() {
        let stream = Self.pair(texts: ("Klaus is reading", "Klaus is reading"))
        #expect(stream.recentlyContains("Klaus is reading", within: 5))
        #expect(!stream.recentlyContains("Klaus is reading", within: 0))
        #expect(!stream.recentlyContains("Klaus is sleeping", within: 5))
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

    @Test("rated poignancy moves the reflection trigger only for memories since the last reflection")
    func ratingsMoveTheTrigger() {
        let embedder = HashingEmbedder()
        var stream = MemoryStream()
        func add(_ text: String) -> Int {
            stream.append(
                kind: .observation, text: text, poignancy: 2, provenance: .observed, embedding: embedder.embed(text),
                at: SimTime(minutes: 0)
            ).id
        }
        let old = add("before the reflection")
        stream.markReflected()
        let new = add("after the reflection")
        #expect(stream.importanceSinceReflection == 2)

        stream.setPoignancy([(old, 10), (new, 10)])
        #expect(stream.importanceSinceReflection == 10, "only the new memory's +8 counts")
        #expect(stream.nodes.map(\.poignancy) == [10, 10], "both scores change")

        stream.setPoignancy([(new, 1)])
        #expect(stream.importanceSinceReflection == 1)
    }
}
