// smallville-run: headless simulation runner. This is the agent's verification loop and the
// CI smoke test, so its output is a single JSON object the agent can paste into a report.
//
//   swift run smallville-run --minutes 2880 --agents 3 --seed 42
//   swift run smallville-run --minutes 240 --agents 3 --fm         (Mac's on-device model)
//   swift run smallville-run --minutes 240 --agents 3 --fm --conversations   (also print transcripts)
//   swift run smallville-run --minutes 1440 --no-party --whisper "klaus: Klaus wants to ask Maria to the dance"
//
// `print` is allowed here and nowhere else in the package.

import Foundation
import SmallvilleCore

#if canImport(FoundationModels)
import SmallvilleFM
#endif

struct Options {
    var minutes = 2 * SimTime.minutesPerDay
    var agents = 3
    var seed: UInt64 = 42
    var useFoundationModels = false
    var includeParty = true
    var whispers: [(AgentID, String)] = []
    var outputPath: String?
    var printConversations = false

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--minutes":
                options.minutes = try Int(required(iterator.next(), for: argument)) ?? options.minutes
            case "--agents":
                options.agents = try Int(required(iterator.next(), for: argument)) ?? options.agents
            case "--seed":
                options.seed = try UInt64(required(iterator.next(), for: argument)) ?? options.seed
            case "--fm":
                options.useFoundationModels = true
            case "--no-party":
                options.includeParty = false
            case "--whisper":
                let raw = try required(iterator.next(), for: argument)
                guard let colon = raw.firstIndex(of: ":") else {
                    throw RunnerError.usage("--whisper expects \"agent: text\"")
                }
                let agent = raw[..<colon].trimmingCharacters(in: .whitespaces)
                let text = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                options.whispers.append((AgentID(agent), text))
            case "--conversations":
                options.printConversations = true
            case "--out":
                options.outputPath = try required(iterator.next(), for: argument)
            case "--help", "-h":
                throw RunnerError.usage(usageText)
            default:
                throw RunnerError.usage("unknown argument \(argument)\n\(usageText)")
            }
        }
        return options
    }

    private static func required(_ value: String?, for flag: String) throws -> String {
        guard let value else { throw RunnerError.usage("\(flag) needs a value") }
        return value
    }

    static let usageText = """
        usage: smallville-run [--minutes N] [--agents N] [--seed N] [--fm] [--no-party]
                              [--whisper "agent: text"]... [--out path.json] [--conversations]
        """
}

enum RunnerError: Error, CustomStringConvertible {
    case usage(String)
    var description: String {
        switch self {
        case .usage(let text): return text
        }
    }
}

struct Report: Codable {
    var gameMinutes: Int
    var agents: Int
    var seed: UInt64
    var brain: String
    var budget: BudgetSummary
    var brainFailures: Int
    var eventCount: Int
    var discoveries: [Discovery]
}

func makeBrain(_ options: Options) throws -> (any AgentBrain, String) {
    guard options.useFoundationModels else { return (StubBrain() as any AgentBrain, "stub") }
    #if canImport(FoundationModels)
    if #available(macOS 26.0, iOS 26.0, *) {
        let info = OnDeviceModelInfo.probe()
        guard info.isAvailable else {
            throw RunnerError.usage("on-device model unavailable: \(info.unavailableReason ?? "unknown")")
        }
        let name = info.variantName ?? "on-device"
        print("Using \(name), context \(info.contextSize ?? 0) tokens")
        return (FoundationModelsBrain() as any AgentBrain, name)
    }
    #endif
    throw RunnerError.usage("--fm needs macOS 26 or later with Apple Intelligence enabled")
}

/// Every conversation as readable text: who, where, the turns, the social acts, what was conveyed.
func transcripts(_ events: [SimEvent], names: [AgentID: String]) -> String {
    func name(_ id: AgentID) -> String { names[id] ?? id.rawValue }
    var blocks: [String] = []
    for event in events {
        guard case .conversed(let conversation, let at, let location) = event else { continue }
        var lines = [
            "--- \(at) @\(location.rawValue): \(name(conversation.initiator)) and \(name(conversation.partner))"
        ]
        lines += conversation.turns.map { "\(name($0.speaker)): \($0.text)" }
        for act in conversation.acts {
            let storyline = act.storyline.map { " [\($0.rawValue)]" } ?? ""
            lines.append("  act: \(act.kind.rawValue) \(name(act.from)) -> \(name(act.to)): \(act.topic)\(storyline)")
        }
        let conveyed = conversation.conveyedStorylines.map(\.rawValue).joined(separator: ", ")
        lines.append("  conveyed: \(conveyed.isEmpty ? "none" : conveyed)")
        lines.append("  \(name(conversation.initiator)) remembers: \(conversation.initiatorSummary)")
        lines.append("  \(name(conversation.partner)) remembers: \(conversation.partnerSummary)")
        blocks.append(lines.joined(separator: "\n"))
    }
    return blocks.isEmpty ? "(no conversations)" : blocks.joined(separator: "\n\n")
}

/// Failed brain calls grouped by kind and reason, most frequent first.
func failureTally(_ events: [SimEvent]) -> [String] {
    var counts: [String: Int] = [:]
    for event in events {
        guard case .brainFailed(_, let kind, let reason, _) = event else { continue }
        counts["\(kind.rawValue): \(reason)", default: 0] += 1
    }
    return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map {
        "\($0.value)x \($0.key)"
    }
}

let valentinesParty = Storyline(
    id: StorylineID("valentines-party"),
    title: "Valentine's Day party at Hobbs Cafe",
    seedText:
        "Isabella is throwing a Valentine's Day party at Hobbs Cafe tomorrow from 5pm to 7pm and wants to invite everyone she knows.",
    seededIn: AgentProfile.isabella.id,
    seededAt: SimTime(minutes: 7 * 60),
    targetLocation: WorldMap.hobbsCafe,
    eventTime: SimTime(minutes: SimTime.minutesPerDay + 17 * 60))

do {
    let options = try Options.parse(CommandLine.arguments)
    let profiles = Array(AgentProfile.sample3.prefix(max(1, min(options.agents, AgentProfile.sample3.count))))
    if options.agents > AgentProfile.sample3.count {
        print("note: only \(AgentProfile.sample3.count) profiles exist yet; running with \(profiles.count)")
    }
    let (brain, brainName) = try makeBrain(options)

    var configuration = Simulation.Configuration()
    configuration.seed = options.seed
    let simulation = Simulation(
        world: .smallvilleSubset(), profiles: profiles, brain: brain, configuration: configuration)

    if options.includeParty {
        await simulation.whisper(valentinesParty)
    }
    for (agent, text) in options.whispers {
        let storyline = Storyline(
            id: StorylineID("whisper-\(agent.rawValue)-\(options.whispers.count)"), title: text, seedText: text,
            seededIn: agent, seededAt: await simulation.now)
        await simulation.whisper(storyline)
    }

    let hours = max(1, options.minutes / 60)
    for _ in 0..<hours {
        try await simulation.run(minutes: 60)
        let snapshot = await simulation.snapshot()
        let where_ = snapshot.agents.map {
            "\($0.name.split(separator: " ").first ?? "?") \($0.emoji) @\($0.location.rawValue)"
        }
        print("\(snapshot.now)  calls=\(snapshot.budget.totalCalls)  \(where_.joined(separator: "  "))")
    }

    let snapshot = await simulation.snapshot()
    let events = await simulation.events
    if options.printConversations {
        let names = Dictionary(profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        print(transcripts(events, names: names))
    }
    let failures = failureTally(events)
    if !failures.isEmpty {
        print("brain failures by kind and reason:\n  " + failures.joined(separator: "\n  "))
    }
    let report = Report(
        gameMinutes: hours * 60, agents: profiles.count, seed: options.seed, brain: brainName,
        budget: snapshot.budget, brainFailures: snapshot.brainFailures, eventCount: snapshot.eventCount,
        discoveries: await simulation.discoveries())

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    if let path = options.outputPath {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        print("wrote \(path)")
    }
    print(String(decoding: data, as: UTF8.self))
    exit(report.budget.withinBudget ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
