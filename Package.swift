// swift-tools-version: 6.2
// VERIFY: PackageDescription 6.2 (Xcode 26+) added `.macOS(.v26)` / `.iOS(.v26)`. If your
// toolchain rejects them, use `.macOS(.v15), .iOS(.v18)` and keep every FoundationModels
// use behind `@available(iOS 26.0, macOS 26.0, *)`; the FM target already does.
import PackageDescription

let package = Package(
    name: "SmallvilleKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SmallvilleCore", targets: ["SmallvilleCore"]),
        .library(name: "SmallvilleFM", targets: ["SmallvilleFM"]),
        .executable(name: "smallville-run", targets: ["smallville-run"]),
    ],
    targets: [
        // Pure simulation: Foundation only. Builds and tests on Linux.
        .target(name: "SmallvilleCore"),
        // Foundation Models adapter. Compiles to an empty module where FoundationModels is unavailable.
        .target(name: "SmallvilleFM", dependencies: ["SmallvilleCore"]),
        // Headless runner used by tests, CI, and the agent's verification loop.
        .executableTarget(name: "smallville-run", dependencies: ["SmallvilleCore", "SmallvilleFM"]),
        .testTarget(name: "SmallvilleCoreTests", dependencies: ["SmallvilleCore"]),
        // Adapter mapping, schemas and prompts with hand-built model output; never calls the model.
        // Every file is wrapped in `#if canImport(FoundationModels)`, so it is empty on Linux.
        .testTarget(name: "SmallvilleFMTests", dependencies: ["SmallvilleFM", "SmallvilleCore"]),
    ],
    swiftLanguageModes: [.v6]
)
