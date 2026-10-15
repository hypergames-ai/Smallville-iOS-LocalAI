import Foundation

/// A seed the player plants (the Valentine's party) and that the detector then follows.
public struct Storyline: Hashable, Sendable, Codable, Identifiable {
    public var id: StorylineID
    public var title: String
    /// The thought as the seeded agent remembers it.
    public var seedText: String
    public var seededIn: AgentID
    public var seededAt: SimTime
    /// Where and when the storyline's event happens, if it has one (used for attendance).
    public var targetLocation: LocationID?
    public var eventTime: SimTime?

    public init(
        id: StorylineID, title: String, seedText: String, seededIn: AgentID, seededAt: SimTime,
        targetLocation: LocationID? = nil, eventTime: SimTime? = nil
    ) {
        self.id = id
        self.title = title
        self.seedText = seedText
        self.seededIn = seededIn
        self.seededAt = seededAt
        self.targetLocation = targetLocation
        self.eventTime = eventTime
    }
}

/// What a conversation accomplished socially. Generated alongside the dialogue so the app
/// never has to re-read transcripts to find out.
public enum SocialActKind: String, Hashable, Sendable, Codable, CaseIterable {
    case invite
    case accept
    case decline
    case inform
    case ask
    case gossip
    case plan
    case disagree
}

/// One social act performed by one agent toward another during a conversation.
public struct SocialAct: Hashable, Sendable, Codable {
    public var kind: SocialActKind
    public var from: AgentID
    public var to: AgentID
    public var topic: String
    public var storyline: StorylineID?

    public init(kind: SocialActKind, from: AgentID, to: AgentID, topic: String, storyline: StorylineID? = nil) {
        self.kind = kind
        self.from = from
        self.to = to
        self.topic = topic
        self.storyline = storyline
    }
}

/// "A told B at time T": one edge of the information-diffusion graph.
public struct DiffusionEdge: Hashable, Sendable, Codable {
    public var from: AgentID
    public var to: AgentID
    public var at: SimTime

    public init(from: AgentID, to: AgentID, at: SimTime) {
        self.from = from
        self.to = to
        self.at = at
    }
}

/// What the detector found for one storyline; the row in the app's Discoveries list.
public struct Discovery: Hashable, Sendable, Codable, Identifiable {
    public var id: String { storyline.rawValue }
    public var storyline: StorylineID
    public var title: String
    /// The agent the storyline was seeded in. The UI labels them; the detector does not exclude them.
    public var host: AgentID
    public var knows: [AgentID]
    public var invited: [AgentID]
    public var accepted: [AgentID]
    public var attended: [AgentID]
    public var diffusion: [DiffusionEdge]
    /// Memory ids per agent that back the claim, for drill-down in the UI.
    public var evidence: [AgentID: [Int]]

    public init(
        storyline: StorylineID, title: String, host: AgentID, knows: [AgentID], invited: [AgentID],
        accepted: [AgentID], attended: [AgentID], diffusion: [DiffusionEdge], evidence: [AgentID: [Int]]
    ) {
        self.storyline = storyline
        self.title = title
        self.host = host
        self.knows = knows
        self.invited = invited
        self.accepted = accepted
        self.attended = attended
        self.diffusion = diffusion
        self.evidence = evidence
    }

    // `evidence` is written as a JSON object keyed by agent id, so an encoder with `.sortedKeys`
    // (the runner's) produces the same bytes on every run. Swift would otherwise encode a
    // dictionary with a struct key as a flat array, which `.sortedKeys` cannot order.

    private enum CodingKeys: String, CodingKey {
        case storyline, title, host, knows, invited, accepted, attended, diffusion, evidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storyline = try container.decode(StorylineID.self, forKey: .storyline)
        title = try container.decode(String.self, forKey: .title)
        host = try container.decode(AgentID.self, forKey: .host)
        knows = try container.decode([AgentID].self, forKey: .knows)
        invited = try container.decode([AgentID].self, forKey: .invited)
        accepted = try container.decode([AgentID].self, forKey: .accepted)
        attended = try container.decode([AgentID].self, forKey: .attended)
        diffusion = try container.decode([DiffusionEdge].self, forKey: .diffusion)
        let raw = try container.decode([String: [Int]].self, forKey: .evidence)
        evidence = Dictionary(uniqueKeysWithValues: raw.map { (AgentID($0.key), $0.value) })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storyline, forKey: .storyline)
        try container.encode(title, forKey: .title)
        try container.encode(host, forKey: .host)
        try container.encode(knows, forKey: .knows)
        try container.encode(invited, forKey: .invited)
        try container.encode(accepted, forKey: .accepted)
        try container.encode(attended, forKey: .attended)
        try container.encode(diffusion, forKey: .diffusion)
        let raw = Dictionary(uniqueKeysWithValues: evidence.map { ($0.key.rawValue, $0.value) })
        try container.encode(raw, forKey: .evidence)
    }
}
