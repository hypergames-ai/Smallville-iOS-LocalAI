import SmallvilleCore
import SmallvilleFM
import SwiftUI
import UIKit

/// Produces the numbers the agent can't get on its own: real per-call latency and token counts
/// on this phone. Writes smallville.benchmark.json and offers it through ShareLink.
struct BenchmarkView: View {
    @Environment(SimulationController.self) private var controller
    @State private var results: [BenchmarkResult] = []
    @State private var isRunning = false
    @State private var status = "Idle"
    @State private var fileURL: URL?
    @State private var callsPerKind = 20

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Available", value: controller.modelInfo.isAvailable ? "Yes" : "No")
                    if let reason = controller.modelInfo.unavailableReason {
                        LabeledContent("Reason", value: reason)
                    }
                    LabeledContent("Variant", value: controller.modelInfo.variantName ?? "unknown (iOS 26)")
                    LabeledContent(
                        "Context", value: controller.modelInfo.contextSize.map { "\($0) tokens" } ?? "unknown")
                }
                Section("Run") {
                    Stepper("Calls per kind: \(callsPerKind)", value: $callsPerKind, in: 5...50, step: 5)
                    Button(isRunning ? "Running…" : "Run benchmark") { Task { await run() } }
                        .disabled(isRunning)
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(
                            BrainCallKind.allCases.filter { kind in results.contains { $0.kind == kind.rawValue } },
                            id: \.self
                        ) { kind in
                            let rows = results.filter { $0.kind == kind.rawValue && $0.ok }
                            let sorted = rows.map(\.wallSeconds).sorted()
                            let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
                            let p95 =
                                sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                            LabeledContent(
                                kind.rawValue,
                                value: String(format: "p50 %.2fs · p95 %.2fs · %d ok", p50, p95, rows.count))
                        }
                    }
                }
                if let fileURL {
                    Section {
                        ShareLink(item: fileURL) {
                            Label("Share smallville.benchmark.json", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Benchmark")
            .onAppear { controller.refreshModelInfo() }
        }
    }

    @MainActor
    private func run() async {
        isRunning = true
        results = []
        defer { isRunning = false }

        // Probe at run time so the benchmark file records the model as it was for these calls.
        let info = controller.refreshModelInfo()
        var collected: [BenchmarkResult] = []
        if info.isAvailable {
            let brain = FoundationModelsBrain()
            let world = WorldMap.smallvilleSubset()
            let sample = sampleContext(world: world)
            let dayPlan = DayPlan(wakeHour: 6, entries: [DayPlanEntry(hour: 9, activity: "open the cafe")])
            for index in 0..<callsPerKind {
                status = "planHour \(index + 1)/\(callsPerKind)"
                collected.append(
                    await measure(.planHour) { try await brain.planHour(sample, dayPlan: dayPlan).receipt })
            }
            let partner = sampleContext(world: world, profile: .klaus)
            let request = ConversationRequest(initiator: sample, partner: partner, maxTurns: 6)
            for index in 0..<callsPerKind {
                status = "converse \(index + 1)/\(callsPerKind)"
                collected.append(await measure(.converse) { try await brain.converse(request).receipt })
            }
        } else {
            status = "Model unavailable; recording that and zero calls."
        }
        results = collected
        status = "Done: \(collected.count) calls"
        write(collected, info: info)
    }

    private func measure(_ kind: BrainCallKind, _ call: () async throws -> BrainCallReceipt) async -> BenchmarkResult {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let receipt = try await call()
            return BenchmarkResult(
                kind: kind.rawValue, inputTokens: receipt.inputTokens, outputTokens: receipt.outputTokens,
                wallSeconds: receipt.wallSeconds, ok: true, error: nil)
        } catch {
            let elapsed = clock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return BenchmarkResult(
                kind: kind.rawValue, inputTokens: 0, outputTokens: 0, wallSeconds: seconds, ok: false,
                error: String(describing: error))
        }
    }

    private func sampleContext(world: WorldMap, profile: AgentProfile = .isabella) -> AgentContext {
        let embedder = HashingEmbedder()
        let now = SimTime(minutes: 9 * 60)
        let texts = [
            "\(profile.name) opened up for the morning and wiped down the counter",
            "\(profile.name) is planning a Valentine's Day party at Hobbs Cafe tomorrow at 5pm",
            "\(profile.name) saw Klaus Mueller reading at a corner table",
        ]
        var stream = MemoryStream()
        for text in texts {
            stream.append(
                kind: .observation, text: text, poignancy: 4, provenance: .observed, embedding: embedder.embed(text),
                at: now)
        }
        let location = world.location(profile.workplace) ?? world.allLocations[0]
        return AgentContext(
            profile: profile, now: now, location: location, relevantMemories: stream.nodes,
            knownLocations: world.publicLocations, activeStorylines: [], dayPlan: nil)
    }

    @MainActor
    private func write(_ results: [BenchmarkResult], info: OnDeviceModelInfo) {
        let file = BenchmarkFile(
            device: UIDevice.current.model, systemVersion: UIDevice.current.systemVersion, model: info,
            recordedAt: ISO8601DateFormatter().string(from: Date()), results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smallville.benchmark.json")
        do {
            try encoder.encode(file).write(to: url)
            fileURL = url
        } catch {
            status = "Could not write benchmark file: \(error)"
        }
    }
}

struct BenchmarkResult: Codable, Hashable {
    var kind: String
    var inputTokens: Int
    var outputTokens: Int
    var wallSeconds: Double
    var ok: Bool
    var error: String?
}

struct BenchmarkFile: Codable {
    var device: String
    var systemVersion: String
    var model: OnDeviceModelInfo
    var recordedAt: String
    var results: [BenchmarkResult]
}
