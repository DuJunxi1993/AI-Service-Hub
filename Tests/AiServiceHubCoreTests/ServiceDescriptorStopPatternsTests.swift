import XCTest
@testable import AiServiceHubCore

final class ServiceDescriptorStopPatternsTests: XCTestCase {
    func testProcessPatternsCollectedFromProbes() {
        let descriptor = ServiceDescriptor(
            name: "X",
            lifecycle: .observed,
            appearance: Appearance(iconSymbol: "x", accent: .gray),
            probes: [
                .processPattern("alpha"),
                .tcpPort(1234),
                .processPattern("beta")
            ]
        )
        XCTAssertEqual(descriptor.processPatterns, ["alpha", "beta"])
    }

    func testEffectiveStopPatternsFallsBackToProbePatterns() {
        let descriptor = ServiceDescriptor(
            name: "X",
            lifecycle: .observed,
            appearance: Appearance(iconSymbol: "x", accent: .gray),
            probes: [.processPattern("alpha")]
        )
        XCTAssertEqual(descriptor.effectiveStopPatterns, ["alpha"])
    }

    func testExplicitStopPatternsWin() {
        let descriptor = ServiceDescriptor(
            name: "X",
            lifecycle: .observed,
            appearance: Appearance(iconSymbol: "x", accent: .gray),
            probes: [.processPattern("alpha")],
            stopProcessPatterns: ["/opt/x", "beta"]
        )
        XCTAssertEqual(descriptor.effectiveStopPatterns, ["/opt/x", "beta"])
        // 探测模式不受影响 —— 它要精确（PID 决定端口反查对象）
        XCTAssertEqual(descriptor.processPatterns, ["alpha"])
    }

    func testHermesStopPatternsCoverItsLayout() {
        let descriptor = HermesPreset.makeDescriptor(home: "/tmp/hermes-home")
        let patterns = descriptor.effectiveStopPatterns
        // Hermes 的进程散落在 supervisor / python / 桌面端，全都在 home 之下
        XCTAssertTrue(patterns.contains("/tmp/hermes-home"))
        XCTAssertTrue(patterns.contains("hermes gateway run"))
    }

    func testDSHStopPatternsCoverWebAndShell() {
        let descriptor = DSHPreset.makeDescriptor(home: "/tmp/dsh-home", port: 3080)
        let patterns = descriptor.effectiveStopPatterns
        XCTAssertTrue(patterns.contains("dsh web"))
        XCTAssertTrue(patterns.contains("DSHShell"))
    }

    func testPresetsCarryDataDirectory() {
        XCTAssertEqual(
            AstrBotPreset.makeDescriptor(dataDirectory: "/tmp/astrbot-data").dataDirectory,
            "/tmp/astrbot-data"
        )
        XCTAssertEqual(
            HermesPreset.makeDescriptor(home: "/tmp/hermes-home").dataDirectory,
            "/tmp/hermes-home"
        )
        XCTAssertEqual(
            DSHPreset.makeDescriptor(home: "/tmp/dsh-home").dataDirectory,
            "/tmp/dsh-home"
        )
    }
}

final class ConfigUpgradeTests: XCTestCase {
    func testShipyardServiceIsRemoved() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "Shipyard",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "shippingbox.fill", accent: .purple),
                managed: .container(ContainerSpec(containerName: "shipyard-1"))
            ),
            ServiceDescriptor(
                name: "AstrBot",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "gearshape.2.fill", accent: .orange)
            )
        ]

        config.upgradeServices()

        XCTAssertEqual(config.services.count, 1)
        XCTAssertEqual(config.services.first?.name, "AstrBot")
    }

    func testDataDirectoryIsInferredForPresets() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "Hermes Agent",
                lifecycle: .observed,
                appearance: Appearance(iconSymbol: "antenna", accent: .purple),
                presetIdentifier: HermesPreset.identifier
            ),
            ServiceDescriptor(
                name: "AstrBot",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "gearshape.2.fill", accent: .orange),
                presetIdentifier: AstrBotPreset.identifier
            ),
            ServiceDescriptor(
                name: "自定义",
                lifecycle: .observed,
                appearance: Appearance(iconSymbol: "x", accent: .gray)
            )
        ]

        config.upgradeServices()

        XCTAssertEqual(config.services[0].dataDirectory, HermesPreset.defaultHome())
        XCTAssertEqual(config.services[1].dataDirectory, "\(NSHomeDirectory())/data")
        // 判断不出来的保持 nil（「打开数据目录」会退回主目录）
        XCTAssertNil(config.services[2].dataDirectory)
    }

    func testExistingDataDirectoryIsKept() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "Hermes Agent",
                lifecycle: .observed,
                appearance: Appearance(iconSymbol: "antenna", accent: .purple),
                dataDirectory: "/custom/path",
                presetIdentifier: HermesPreset.identifier
            )
        ]

        config.upgradeServices()

        XCTAssertEqual(config.services[0].dataDirectory, "/custom/path")
    }
}
