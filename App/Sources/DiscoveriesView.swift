import SmallvilleCore
import SwiftUI

/// The nav-list of detected behaviors, one row per planted storyline, with drill-down to evidence.
struct DiscoveriesView: View {
    @Environment(SimulationController.self) private var controller

    var body: some View {
        NavigationStack {
            Group {
                if controller.discoveries.isEmpty {
                    ContentUnavailableView(
                        "Nothing yet", systemImage: "sparkles",
                        description: Text("Start the simulation from the Town tab. Discoveries appear as storylines spread."))
                } else {
                    List(controller.discoveries) { discovery in
                        NavigationLink(value: discovery) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(discovery.title).font(.headline)
                                Text(
                                    "\(discovery.knows.count) know · \(discovery.invited.count) invited · \(discovery.accepted.count) accepted · \(discovery.attended.count) showed up"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Discoveries")
            .navigationDestination(for: Discovery.self) { discovery in
                DiscoveryDetailView(discovery: discovery)
            }
        }
    }
}

struct DiscoveryDetailView: View {
    @Environment(SimulationController.self) private var controller
    let discovery: Discovery

    var body: some View {
        List {
            Section("Who knows") {
                ForEach(discovery.knows, id: \.self) { agent in
                    NavigationLink(controller.name(of: agent)) {
                        EvidenceView(agent: agent, memoryIDs: discovery.evidence[agent] ?? [])
                    }
                }
            }
            Section("How it spread") {
                if discovery.diffusion.isEmpty {
                    Text("No one has passed it on yet.").foregroundStyle(.secondary)
                }
                ForEach(discovery.diffusion, id: \.self) { edge in
                    Text("\(controller.name(of: edge.from)) told \(controller.name(of: edge.to)) · \(edge.at)")
                }
            }
            Section("Outcome") {
                LabeledContent("Invited", value: names(discovery.invited))
                LabeledContent("Accepted", value: names(discovery.accepted))
                LabeledContent("Showed up", value: names(discovery.attended))
            }
        }
        .navigationTitle(discovery.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: exportText) { Label("Report", systemImage: "square.and.arrow.up") }
        }
    }

    private func names(_ agents: [AgentID]) -> String {
        agents.isEmpty ? "—" : agents.map { controller.name(of: $0) }.joined(separator: ", ")
    }

    private var exportText: String {
        var lines = ["# \(discovery.title)", ""]
        lines.append("Knows: \(names(discovery.knows))")
        lines.append("Invited: \(names(discovery.invited))")
        lines.append("Accepted: \(names(discovery.accepted))")
        lines.append("Showed up: \(names(discovery.attended))")
        lines.append("")
        lines.append("Diffusion:")
        for edge in discovery.diffusion {
            lines.append("- \(controller.name(of: edge.from)) → \(controller.name(of: edge.to)) at \(edge.at)")
        }
        return lines.joined(separator: "\n")
    }
}

/// The memories that back a claim about one agent.
struct EvidenceView: View {
    @Environment(SimulationController.self) private var controller
    let agent: AgentID
    let memoryIDs: [Int]
    @State private var nodes: [MemoryNode] = []

    var body: some View {
        List(nodes) { node in
            VStack(alignment: .leading, spacing: 4) {
                Text(node.text)
                Text("\(node.created) · \(node.kind.rawValue) · poignancy \(node.poignancy) · \(provenance(node))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(controller.name(of: agent))
        .task {
            let all = await controller.memories(of: agent)
            let wanted = Set(memoryIDs)
            nodes = all.filter { wanted.contains($0.id) }
        }
    }

    private func provenance(_ node: MemoryNode) -> String {
        switch node.provenance {
        case .observed: return "observed"
        case .told(let by, _): return "told by \(controller.name(of: by))"
        case .reflected: return "reflected"
        case .whispered: return "whispered by you"
        }
    }
}
