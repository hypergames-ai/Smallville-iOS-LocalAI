import Foundation
import Testing

@testable import SmallvilleCore

@Suite("Storyline detector (pure)")
struct StorylineDetectorTests {
    static let party = ValentinesPartyTests.party
    static let isabella = AgentProfile.isabella.id
    static let klaus = AgentProfile.klaus.id
    static let maria = AgentProfile.maria.id

    private static func samples(_ agent: AgentID, at minutes: [Int], location: LocationID = WorldMap.hobbsCafe)
        -> [PositionSample]
    {
        minutes.map { PositionSample(agent: agent, location: location, at: SimTime(minutes: $0)) }
    }

    /// Isabella was whispered the party; Klaus was told by her in two separate conversations.
    private static func memories() -> [AgentID: MemoryStream] {
        let embedder = HashingEmbedder()
        var hostStream = MemoryStream()
        hostStream.append(
            kind: .whisper, text: party.seedText, poignancy: 8, provenance: .whispered, storylines: [party.id],
            embedding: embedder.embed(party.seedText), at: SimTime(minutes: 420))
        var listenerStream = MemoryStream()
        listenerStream.append(
            kind: .chat, text: "heard about the party", poignancy: 5,
            provenance: .told(by: isabella, at: SimTime(minutes: 790)), storylines: [party.id],
            embedding: embedder.embed("heard about the party"), at: SimTime(minutes: 790))
        listenerStream.append(
            kind: .chat, text: "reminded about the party", poignancy: 5,
            provenance: .told(by: isabella, at: SimTime(minutes: 910)), storylines: [party.id],
            embedding: embedder.embed("reminded about the party"), at: SimTime(minutes: 910))
        return [isabella: hostStream, klaus: listenerStream, maria: MemoryStream()]
    }

    @Test("attendance needs the dwell: two ticks in the window count, one does not, outside does not")
    func attendanceDwell() {
        let eventMinute = Self.party.eventTime?.minutes ?? 0
        let positions =
            Self.samples(Self.isabella, at: [eventMinute - 10, eventMinute])
            + Self.samples(Self.klaus, at: [eventMinute + 30])
            + Self.samples(Self.maria, at: [eventMinute - 61, eventMinute + 61])

        let strict = StorylineDetector.detect(
            Self.party, memories: Self.memories(), events: [], positions: positions)
        #expect(strict.attended == [Self.isabella])
        #expect(strict.host == Self.isabella)
        #expect(strict.attended.contains(strict.host), "the host attended her own party")

        let lenient = StorylineDetector.detect(
            Self.party, memories: Self.memories(), events: [], positions: positions, minimumDwellSamples: 1)
        #expect(lenient.attended == [Self.isabella, Self.klaus])
    }

    @Test("diffusion keeps the earliest edge per pair")
    func diffusionDedupe() {
        let discovery = StorylineDetector.detect(Self.party, memories: Self.memories(), events: [], positions: [])
        #expect(discovery.knows == [Self.isabella, Self.klaus])
        #expect(discovery.diffusion == [DiffusionEdge(from: Self.isabella, to: Self.klaus, at: SimTime(minutes: 790))])
        #expect(discovery.evidence[Self.klaus]?.count == 2)
    }

    @Test("invited and accepted come from social acts in conversed events")
    func socialActs() {
        let conversation = Conversation(
            initiator: Self.isabella, partner: Self.maria, turns: [],
            acts: [
                SocialAct(kind: .invite, from: Self.isabella, to: Self.maria, topic: "party", storyline: Self.party.id),
                SocialAct(kind: .accept, from: Self.maria, to: Self.isabella, topic: "party", storyline: Self.party.id),
                SocialAct(
                    kind: .invite, from: Self.isabella, to: Self.klaus, topic: "other", storyline: StorylineID("x")),
            ],
            conveyedStorylines: [Self.party.id], initiatorSummary: "", partnerSummary: "")
        let events: [SimEvent] = [.conversed(conversation, at: SimTime(minutes: 800), location: WorldMap.hobbsCafe)]
        let discovery = StorylineDetector.detect(Self.party, memories: Self.memories(), events: events, positions: [])
        #expect(discovery.invited == [Self.maria])
        #expect(discovery.accepted == [Self.maria])
    }

    @Test("a discovery encodes to the same bytes every time and round-trips")
    func stableJSON() throws {
        let discovery = StorylineDetector.detect(Self.party, memories: Self.memories(), events: [], positions: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let first = try encoder.encode(discovery)
        let second = try encoder.encode(discovery)
        #expect(first == second)

        let text = String(decoding: first, as: UTF8.self)
        #expect(text.contains("\"evidence\" : {"), "evidence is a JSON object keyed by agent id")
        #expect(text.contains("\"host\" : \"isabella\""))

        let decoded = try JSONDecoder().decode(Discovery.self, from: first)
        #expect(decoded == discovery)
    }
}
