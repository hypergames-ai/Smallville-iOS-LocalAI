import Foundation

/// Finds what happened to a planted storyline. A pure function of the simulation's records:
/// who knows (memory tags), who told whom (provenance), who was invited and accepted
/// (social acts), and who showed up (position log).
public enum StorylineDetector {
    /// `attended` needs at least `minimumDwellSamples` position samples (one per tick) at the
    /// venue inside the window, so passing through does not count. The host is not excluded;
    /// `Discovery.host` says who they are.
    public static func detect(
        _ storyline: Storyline, memories: [AgentID: MemoryStream], events: [SimEvent], positions: [PositionSample],
        attendanceWindowMinutes: Int = 60, minimumDwellSamples: Int = 2
    ) -> Discovery {
        var knows: [AgentID] = []
        var evidence: [AgentID: [Int]] = [:]
        // The earliest time each pair told each other; one conversation can leave several told-by memories.
        var firstTold: [AgentID: [AgentID: SimTime]] = [:]

        for (agent, stream) in memories.sorted(by: { $0.key < $1.key }) {
            let nodes = stream.nodes(for: storyline.id)
            guard !nodes.isEmpty else { continue }
            knows.append(agent)
            evidence[agent] = nodes.map(\.id)
            for node in nodes {
                if case .told(let by, let at) = node.provenance {
                    if firstTold[by, default: [:]][agent].map({ at < $0 }) ?? true {
                        firstTold[by, default: [:]][agent] = at
                    }
                }
            }
        }
        var edges: [DiffusionEdge] = []
        for (from, tos) in firstTold.sorted(by: { $0.key < $1.key }) {
            for (to, at) in tos.sorted(by: { $0.key < $1.key }) {
                edges.append(DiffusionEdge(from: from, to: to, at: at))
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
            var dwell: [AgentID: Int] = [:]
            for sample in positions where sample.location == location && window.contains(sample.at.minutes) {
                dwell[sample.agent, default: 0] += 1
            }
            attended = dwell.filter { $0.value >= max(1, minimumDwellSamples) }.keys.sorted()
        }

        return Discovery(
            storyline: storyline.id, title: storyline.title, host: storyline.seededIn, knows: knows,
            invited: invited.sorted(), accepted: accepted.sorted(), attended: attended,
            diffusion: edges.sorted { ($0.at, $0.from, $0.to) < ($1.at, $1.from, $1.to) }, evidence: evidence)
    }
}
