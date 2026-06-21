// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Fonim",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Fonim", targets: ["VibeVoiceBatch"]),
        .executable(name: "VibeVoiceBatchCoreChecks", targets: ["VibeVoiceBatchCoreChecks"]),
        .library(name: "VibeVoiceBatchCore", targets: ["VibeVoiceBatchCore"])
    ],
    targets: [
        .target(name: "VibeVoiceBatchCore"),
        .executableTarget(
            name: "VibeVoiceBatch",
            dependencies: ["VibeVoiceBatchCore"]
        ),
        .executableTarget(
            name: "VibeVoiceBatchCoreChecks",
            dependencies: ["VibeVoiceBatchCore"]
        )
    ]
)
