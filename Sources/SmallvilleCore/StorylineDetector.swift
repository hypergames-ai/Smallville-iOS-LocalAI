import Foundation

/// Finds what happened to a planted storyline. A pure function of the simulation's records:
/// who knows (memory tags), who told whom (provenance), who was invited and accepted
/// (social acts), and who showed up (position log).
public enum StorylineDetector {
    public static func detect(
        _ storyline: Storyline, memories: [AgentID: MemoryStream], events: [SimEvent], positions: [PositionSample],
        attendanceWindowMinutes: Int = 60
    ) -> Discovery {
        var knows: [AgentID] = []
        var evidence: [AgentID: [Int]] = [:]
        var edges: [DiffusionEdge] = []

        for (agent, stream) in memories.sorted(by: { $0.key < $1.key }) {
            let nodes = stream.nodes(for: storyline.id)
            guard !nodes.isEmpty else { continue }
            knows.append(agent)
            evidence[agent] = nodes.map(\.id)
            for node in nodes {
                if case .told(let by, let at) = node.provenance {
                    edges.append(DiffusionEdge(from: by, to: agent, at: at))
                }
            }
        }

        var invited = Set<AgentID>()
        var accepted = Set<AgentID>()
        for event in events {
            guard case .conversed(let conversation, _, _) = event else { continue }
            for act in conversation.acts where act.storyline == storyline.id {
                switch act.kind {
                case .invite: invited.insert(act.to)
                case .accept: accepted.insert(act.from)
                default: break
                }
            }
        }

        var attended: [AgentID] = []
        if let location = storyline.targetLocation, let time = storyline.eventTime {
            let window = (time.minutes - attendanceWindowMinutes)...(time.minutes + attendanceWindowMinutes)
            attended = Set(
                positions.filter { $0.location == location && window.contains($0.at.minutes) }.map(\.agent)
            ).sorted()
        }

        return Discovery(
            storyline: storyline.id, title: storyline.title, knows: knows, invited: invited.sorted(),
            accepted: accepted.sorted(), attended: attended, diffusion: edges.sorted { $0.at < $1.at },
            evidence: evidence)
    }
}
