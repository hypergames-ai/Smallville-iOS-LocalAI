import Foundation

/// Everything that happens in the town, in order. The detector and the UI read this, never
/// the agents' private state.
public enum SimEvent: Hashable, Sendable, Codable {
    case moved(agent: AgentID, to: LocationID, at: SimTime)
    case acted(agent: AgentID, action: PlannedAction, at: SimTime)
    case conversed(Conversation, at: SimTime, location: LocationID)
    case reflected(agent: AgentID, reflection: Reflection, at: SimTime)
    case whispered(agent: AgentID, storyline: StorylineID, at: SimTime)
    case brainFailed(agent: AgentID, kind: BrainCallKind, reason: String, at: SimTime)

    public var time: SimTime {
        switch self {
        case .moved(_, _, let at), .acted(_, _, let at), .conversed(_, let at, _),
            .reflected(_, _, let at), .whispered(_, _, let at), .brainFailed(_, _, _, let at):
            return at
        }
    }
}

/// Where an agent was at a tick. Attendance is computed from these.
public struct PositionSample: Hashable, Sendable, Codable {
    public var agent: AgentID
    public var location: LocationID
    public var at: SimTime

    public init(agent: AgentID, location: LocationID, at: SimTime) {
        self.agent = agent
        self.location = location
        self.at = at
    }
}
