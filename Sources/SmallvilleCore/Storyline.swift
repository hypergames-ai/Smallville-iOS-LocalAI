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
    public var knows: [AgentID]
    public var invited: [AgentID]
    public var accepted: [AgentID]
    public var attended: [AgentID]
    public var diffusion: [DiffusionEdge]
    /// Memory ids per agent that back the claim, for drill-down in the UI.
    public var evidence: [AgentID: [Int]]

    public init(
        storyline: StorylineID, title: String, knows: [AgentID], invited: [AgentID], accepted: [AgentID],
        attended: [AgentID], diffusion: [DiffusionEdge], evidence: [AgentID: [Int]]
    ) {
        self.storyline = storyline
        self.title = title
        self.knows = knows
        self.invited = invited
        self.accepted = accepted
        self.attended = attended
        self.diffusion = diffusion
        self.evidence = evidence
    }
}
