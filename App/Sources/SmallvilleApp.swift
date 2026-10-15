import SwiftUI

@main
struct SmallvilleApp: App {
    enum AppTab: String, Hashable {
        case town, discoveries, benchmark
    }

    @State private var controller = SimulationController()
    @State private var selectedTab: AppTab =
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:)) ?? .town

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Town", systemImage: "map", value: AppTab.town) {
                    TownView()
                }
                Tab("Discoveries", systemImage: "sparkles", value: AppTab.discoveries) {
                    DiscoveriesView()
                }
                Tab("Benchmark", systemImage: "gauge.with.dots.needle.67percent", value: AppTab.benchmark) {
                    BenchmarkView()
                }
            }
            .environment(controller)
            .task { autorunIfRequested() }
        }
    }

    /// `-autorunMinutes N` (a launch argument, read through UserDefaults) starts the stub brain
    /// and stops after N game-minutes, so a run can be checked without tapping.
    private func autorunIfRequested() {
        let minutes = UserDefaults.standard.integer(forKey: "autorunMinutes")
        guard minutes > 0, !controller.isRunning else { return }
        controller.brainChoice = .stub
        controller.stopAfterMinutes = minutes
        controller.start()
    }
}
