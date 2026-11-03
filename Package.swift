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
        // 纯逻辑层：不 import SwiftUI，可独立单元测试
        .target(
            name: "AiServiceHubCore",
            path: "Sources/AiServiceHubCore",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "AiServiceHub",
            dependencies: ["AiServiceHubCore"],
            path: "Sources/AiServiceHub",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AiServiceHubCoreTests",
            dependencies: ["AiServiceHubCore"],
            path: "Tests/AiServiceHubCoreTests"
        )
    ]
)
