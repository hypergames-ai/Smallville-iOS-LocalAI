import SwiftUI

@main
struct SmallvilleApp: App {
    @State private var controller = SimulationController()

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Town", systemImage: "map") {
                    TownView()
                }
                Tab("Discoveries", systemImage: "sparkles") {
                    DiscoveriesView()
                }
                Tab("Benchmark", systemImage: "gauge.with.dots.needle.67percent") {
                    BenchmarkView()
                }
            }
            .environment(controller)
        }
    }
}
