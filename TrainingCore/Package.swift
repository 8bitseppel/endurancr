// swift-tools-version: 6.0
import PackageDescription

// TrainingCore: pure, platform-agnostic training logic (VDOT, plan generation,
// adaptation). No UI, no HealthKit, no networking — so it builds and runs on any
// host without Apple hardware. The iOS/watchOS apps depend on this package.
//
// Note: XCTest / Swift Testing are unavailable with the standalone Command Line
// Tools, so the checks run as an executable (`swift run TrainingCoreChecks`).
// Under full Xcode these can move into a normal test target.
let package = Package(
    name: "TrainingCore",
    products: [
        .library(name: "TrainingCore", targets: ["TrainingCore"]),
        .executable(name: "TrainingCoreChecks", targets: ["TrainingCoreChecks"]),
    ],
    targets: [
        .target(name: "TrainingCore"),
        .executableTarget(
            name: "TrainingCoreChecks",
            dependencies: ["TrainingCore"]
        ),
    ]
)
