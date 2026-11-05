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
        XCTAssertEqual(descriptor.stopPatterns, ["alpha"])
    }

    func testExplicitStopPatternsWin() {
        let descriptor = ServiceDescriptor(
            name: "X",
            lifecycle: .observed,
            appearance: Appearance(iconSymbol: "x", accent: .gray),
            probes: [.processPattern("alpha")],
            stopProcessPatterns: ["/opt/x", "beta"]
        )
        XCTAssertEqual(descriptor.stopPatterns, ["/opt/x", "beta"])
        // 探测模式不受影响 —— 它要精确（PID 决定端口反查对象）
        XCTAssertEqual(descriptor.processPatterns, ["alpha"])
    }

    func testHermesStopPatternsCoverItsLayout() {
        let descriptor = HermesPreset.makeDescriptor(home: "/tmp/hermes-home")
        let patterns = descriptor.stopPatterns
        // Hermes 的进程散落在 supervisor / python / 桌面端，全都在 home 之下
        XCTAssertTrue(patterns.contains("/tmp/hermes-home"))
        XCTAssertTrue(patterns.contains("hermes gateway run"))
    }

    func testDSHStopPatternsCoverWebAndShell() {
        let descriptor = DSHPreset.makeDescriptor(home: "/tmp/dsh-home", port: 3080)
        let patterns = descriptor.stopPatterns
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

final class DisplayCommandTests: XCTestCase {
    /// 命令行里内嵌大段脚本时要压成单行
    func testNewlinesAreFlattened() {
        let command = "line one\nline two\nline three"
        let display = ProbeEvaluator.displayCommand(command)
        XCTAssertFalse(display.contains("\n"))
        XCTAssertTrue(display.contains("line one line two line three"))
    }

    /// 超长命令行要截断
    func testLongCommandIsTruncated() {
        let command = String(repeating: "x", count: 500)
        let display = ProbeEvaluator.displayCommand(command, limit: 100)
        XCTAssertEqual(display.count, 101)  // 100 + 省略号
        XCTAssertTrue(display.hasSuffix("…"))
    }

    /// 短命令行原样保留
    func testShortCommandIsUnchanged() {
        XCTAssertEqual(ProbeEvaluator.displayCommand("/usr/bin/sleep 30"), "/usr/bin/sleep 30")
    }

    /// Hermes 的 osascript 包装器（含几百行 Python）不能撑爆详情页
    func testHermesStyleWrapperIsBounded() {
        let embedded = (0..<200).map { "line \($0) import os" }.joined(separator: "\n")
        let command = "/usr/bin/osascript -l JavaScript -e '\(embedded)'"
        let display = ProbeEvaluator.displayCommand(command)
        XCTAssertLessThanOrEqual(display.count, 161)
        XCTAssertFalse(display.contains("\n"))
    }

    /// 首尾空白要去掉
    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(ProbeEvaluator.displayCommand("  hello  "), "hello")
    }
}

final class StopPatternsTests: XCTestCase {
    /// 可管理的进程服务：停止用完整的 processMatch（探测只用了其中一条）
    func testManagedProcessUsesFullProcessMatch() {
        let descriptor = ServiceDescriptor(
            name: "AstrBot",
            lifecycle: .managed,
            appearance: Appearance(iconSymbol: "x", accent: .orange),
            managed: .process(ProcessSpec(
                executable: "/usr/local/bin/astrbot",
                arguments: ["run"],
                processMatch: ["/usr/local/bin/astrbot run", "/opt/homebrew/bin/astrbot run"]
            )),
            probes: [.processPattern("/usr/local/bin/astrbot run")]
        )
        XCTAssertEqual(descriptor.stopPatterns.count, 2)
        XCTAssertTrue(descriptor.stopPatterns.contains("/opt/homebrew/bin/astrbot run"))
    }

    /// 纯监控服务：停止用显式配置的 stopProcessPatterns
    func testObservedUsesExplicitStopPatterns() {
        let descriptor = ServiceDescriptor(
            name: "Hermes",
            lifecycle: .observed,
            appearance: Appearance(iconSymbol: "x", accent: .purple),
            probes: [.processPattern("hermes gateway run")],
            stopProcessPatterns: ["/tmp/hermes-home", "hermes gateway run"]
        )
        XCTAssertEqual(descriptor.stopPatterns, ["/tmp/hermes-home", "hermes gateway run"])
    }

    /// 纯监控服务没配 stopProcessPatterns → 退回探测模式
    func testObservedFallsBackToProbePatterns() {
        let descriptor = ServiceDescriptor(
            name: "Hermes",
            lifecycle: .observed,
            appearance: Appearance(iconSymbol: "x", accent: .purple),
            probes: [.processPattern("hermes gateway run")]
        )
        XCTAssertEqual(descriptor.stopPatterns, ["hermes gateway run"])
    }

    /// 容器服务没有进程模式 → 空
    func testContainerHasNoProcessPatterns() {
        let descriptor = ServiceDescriptor(
            name: "NapCat",
            lifecycle: .managed,
            appearance: Appearance(iconSymbol: "x", accent: .cyan),
            managed: .container(ContainerSpec(containerName: "napcat-1"))
        )
        XCTAssertTrue(descriptor.stopPatterns.isEmpty)
    }
}
