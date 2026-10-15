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
    private(set) var isRunning = false
    private(set) var lastError: String?
    var brainChoice: BrainChoice = .stub
    let modelInfo = OnDeviceModelInfo.probe()

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

    func start() {
        guard !isRunning else { return }
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
        // The sim only runs in the foreground; background inference is rate-limited by the system.
        UIApplication.shared.isIdleTimerDisabled = true

        task = Task { [weak self] in
            await simulation.whisper(Self.valentinesParty)
            while !Task.isCancelled {
                do {
                    try await simulation.run(minutes: 60)
                } catch {
                    await MainActor.run { self?.lastError = String(describing: error) }
                    break
                }
                let snapshot = await simulation.snapshot()
                let discoveries = await simulation.discoveries()
                await MainActor.run {
                    self?.snapshot = snapshot
                    self?.discoveries = discoveries
                }
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
