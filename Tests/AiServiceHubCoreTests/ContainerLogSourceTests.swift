import XCTest
@testable import AiServiceHubCore

final class ContainerLogSourceTests: XCTestCase {
    // MARK: - 配置升级

    func testUpgradeConvertsDockerFollowCommandToPolling() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "NapCat",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "x", accent: .gray),
                managed: .container(ContainerSpec(containerName: "napcat-napcat-1")),
                logSources: [
                    .command(
                        id: "napcat-logs",
                        label: "容器日志",
                        executable: "docker",
                        arguments: ["logs", "--tail", "500", "-f", "napcat-napcat-1"]
                    )
                ]
            )
        ]

        config.upgradeLogSources()

        guard case .dockerLogs(let containerName) = config.services[0].logSources[0].kind else {
            return XCTFail("期望升级为轮询式容器日志")
        }
        XCTAssertEqual(containerName, "napcat-napcat-1")
    }

    func testUpgradeAddsWebUIKindForNapCat() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "NapCat",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "x", accent: .gray),
                managed: .container(ContainerSpec(containerName: "napcat-napcat-1")),
                logSources: [
                    .dockerLogs(id: "l", label: "容器日志", containerName: "napcat-napcat-1")
                ]
            )
        ]

        config.upgradeLogSources()

        XCTAssertEqual(config.services[0].logSources[0].webUIKind, .napCat)
    }

    func testUpgradeAddsWebUIKindForAstrBotLog() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "AstrBot",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "x", accent: .gray),
                logSources: [.file(id: "astrbot-log", label: "AstrBot 日志", path: "/tmp/a.log")]
            )
        ]

        config.upgradeLogSources()

        XCTAssertEqual(config.services[0].logSources[0].webUIKind, .astrbot)
    }

    func testUpgradeLeavesUnknownContainersAlone() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "Other",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "x", accent: .gray),
                logSources: [
                    .dockerLogs(id: "l", label: "容器日志", containerName: "some-random-container")
                ]
            )
        ]

        config.upgradeLogSources()

        // 未知容器不应被强加提取规则
        XCTAssertNil(config.services[0].logSources[0].webUIKind)
    }

    func testUpgradeIsIdempotent() {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "NapCat",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "x", accent: .gray),
                logSources: [
                    .dockerLogs(id: "l", label: "容器日志", containerName: "napcat-napcat-1")
                ]
            )
        ]

        config.upgradeLogSources()
        let first = config.services[0].logSources[0]
        config.upgradeLogSources()
        XCTAssertEqual(config.services[0].logSources[0], first)
    }

    // MARK: - 编解码

    func testDockerLogsRoundTrip() throws {
        let source = LogSourceSpec.dockerLogs(
            id: "napcat-logs",
            label: "容器日志",
            containerName: "napcat-napcat-1",
            webUIKind: .napCat
        )
        let data = try ConfigStore.encoder.encode(source)
        let decoded = try ConfigStore.decoder.decode(LogSourceSpec.self, from: data)

        XCTAssertEqual(decoded.id, "napcat-logs")
        XCTAssertEqual(decoded.webUIKind, .napCat)
        guard case .dockerLogs(let name) = decoded.kind else {
            return XCTFail("期望 dockerLogs")
        }
        XCTAssertEqual(name, "napcat-napcat-1")
    }

    func testOldCommandSourceStillDecodes() throws {
        // 旧配置文件里是 command 形态，必须仍能读出来（再由 upgradeLogSources 升级）
        let json = """
        {
          "id": "napcat-logs",
          "label": "容器日志",
          "kind": "command",
          "executable": "docker",
          "arguments": ["logs", "--tail", "500", "-f", "napcat-napcat-1"]
        }
        """
        let decoded = try ConfigStore.decoder.decode(LogSourceSpec.self, from: Data(json.utf8))
        guard case .command(let executable, let arguments) = decoded.kind else {
            return XCTFail("期望 command")
        }
        XCTAssertEqual(executable, "docker")
        XCTAssertEqual(arguments.last, "napcat-napcat-1")
    }
}
