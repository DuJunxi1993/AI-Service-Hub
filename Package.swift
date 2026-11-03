// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AiServiceHub",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AiServiceHub", targets: ["AiServiceHub"])
    ],
    targets: [
        .executableTarget(
            name: "AiServiceHub",
            path: "Sources/AiServiceHub",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
