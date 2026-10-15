import Foundation
import Observation
import SmallvilleCore
import SmallvilleFM
import UIKit

/// Owns the simulation for the UI: starts it, advances it one game-hour at a time while the app
/// is in the foreground, and publishes snapshots and discoveries for the views.
@MainActor
@Observable
final class SimulationController {
    enum BrainChoice: String, CaseIterable, Identifiable {
        case stub = "Stub (deterministic)"
        case onDevice = "On-device model"
        var id: String { rawValue }
    }

    private(set) var snapshot: Simulation.Snapshot?
    private(set) var discoveries: [Discovery] = []
    /// Conversations held so far this run, counted from `.conversed` events (the snapshot has no count).
    private(set) var conversationCount = 0
    private(set) var isRunning = false
    private(set) var lastError: String?
    var brainChoice: BrainChoice = .stub
    /// When set, the run loop ends after this many game-minutes from the start (used by `-autorunMinutes`).
    var stopAfterMinutes: Int?

    /// Toggle-friendly view of `brainChoice`; off means the deterministic stub brain.
    var useOnDeviceModel: Bool {
        get { brainChoice == .onDevice }
        set { brainChoice = newValue ? .onDevice : .stub }
    }
    /// The latest probe of the on-device model. Re-probed on demand because a probe taken at launch
    /// on a fresh simulator can report a zero context size.
    private(set) var modelInfo = OnDeviceModelInfo.probe()

    private var simulation: Simulation?
    private var task: Task<Void, Never>?

    static let valentinesParty = Storyline(
        id: StorylineID("valentines-party"),
        title: "Valentine's Day party at Hobbs Cafe",
        seedText:
            "Isabella is throwing a Valentine's Day party at Hobbs Cafe tomorrow from 5pm to 7pm and wants to invite everyone she knows.",
        seededIn: AgentProfile.isabella.id,
        seededAt: SimTime(minutes: 7 * 60),
        targetLocation: WorldMap.hobbsCafe,
        eventTime: SimTime(minutes: SimTime.minutesPerDay + 17 * 60))

    /// Probes the on-device model again and publishes the result.
    @discardableResult
    func refreshModelInfo() -> OnDeviceModelInfo {
        modelInfo = OnDeviceModelInfo.probe()
        return modelInfo
    }

    func start() {
        guard !isRunning else { return }
        let modelInfo = refreshModelInfo()
        let brain: any AgentBrain
        switch brainChoice {
        case .stub:
            brain = StubBrain()
        case .onDevice:
            guard modelInfo.isAvailable else {
                lastError = "On-device model unavailable: \(modelInfo.unavailableReason ?? "unknown")"
                return
            }
            brain = FoundationModelsBrain()
        }

        let simulation = Simulation(world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: brain)
        self.simulation = simulation
        isRunning = true
        lastError = nil
        conversationCount = 0
        // The sim only runs in the foreground; background inference is rate-limited by the system.
        UIApplication.shared.isIdleTimerDisabled = true

        let stopAfterMinutes = self.stopAfterMinutes
        task = Task { [weak self] in
            await simulation.whisper(Self.valentinesParty)
            // The sim starts mid-morning, so the stop point is measured from the start, not from minute 0.
            let startMinutes = await simulation.now.minutes
            while !Task.isCancelled {
                do {
                    try await simulation.run(minutes: 60)
                } catch {
                    await MainActor.run { self?.lastError = String(describing: error) }
                    break
                }
                let snapshot = await simulation.snapshot()
                let discoveries = await simulation.discoveries()
                let conversations = await simulation.events.reduce(0) { count, event in
                    if case .conversed = event { return count + 1 }
                    return count
                }
                await MainActor.run {
                    self?.snapshot = snapshot
                    self?.discoveries = discoveries
                    self?.conversationCount = conversations
                }
                if let stopAfterMinutes, snapshot.now.minutes - startMinutes >= stopAfterMinutes { break }
            }
            await MainActor.run {
                self?.isRunning = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func memories(of agent: AgentID) async -> [MemoryNode] {
        await simulation?.memories(of: agent) ?? []
    }

    func name(of agent: AgentID) -> String {
        AgentProfile.sample3.first { $0.id == agent }?.name ?? agent.rawValue
    }
}
