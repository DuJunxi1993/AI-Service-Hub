import XCTest
@testable import AiServiceHubCore

final class AppConfigTests: XCTestCase {
    func testRoundTrip() throws {
        var config = AppConfig()
        config.preferences.themeMode = .dark
        config.preferences.pollingIntervalSeconds = 12
        config.preferences.autoStartAllServices = false
        config.preferences.sidebarOrder = [UUID(), UUID()]

        let astrBot = AstrBotPreset.makeDescriptor()
        config.services = [astrBot, HermesPreset.makeDescriptor(), DSHPreset.makeDescriptor()]

        config.ownedProcesses = [
            OwnedProcessRecord(
                serviceID: astrBot.id,
                pid: 4242,
                startTimeToken: "123.456",
                executable: "/usr/local/bin/astrbot",
                arguments: ["run"],
                detached: true
            )
        ]

        let data = try ConfigStore.encoder.encode(config)
        let decoded = try ConfigStore.decoder.decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, AppConfig.currentSchemaVersion)
        XCTAssertEqual(decoded.preferences.themeMode, .dark)
        XCTAssertEqual(decoded.preferences.pollingIntervalSeconds, 12)
        XCTAssertFalse(decoded.preferences.autoStartAllServices)
        XCTAssertEqual(decoded.services.count, 3)
        XCTAssertEqual(decoded.services[0].name, "AstrBot")
        XCTAssertEqual(decoded.services[0].lifecycle, .managed)
        XCTAssertEqual(decoded.services[0].driver, .process)
        XCTAssertEqual(decoded.services[1].lifecycle, .observed)
        XCTAssertEqual(decoded.services[2].lifecycle, .observed)
        XCTAssertEqual(decoded.ownedProcesses.first?.pid, 4242)
    }

    func testManagedSpecKeepsDriverDiscriminator() throws {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "C",
                lifecycle: .managed,
                appearance: Appearance(iconSymbol: "x", accent: .gray),
                managed: .container(ContainerSpec(containerName: "abc", stopOnAppQuit: false))
            )
        ]
        let data = try ConfigStore.encoder.encode(config)
        let decoded = try ConfigStore.decoder.decode(AppConfig.self, from: data)
        guard case .container(let spec) = decoded.services[0].managed else {
            return XCTFail("期望 container 子类型")
        }
        XCTAssertEqual(spec.containerName, "abc")
        XCTAssertFalse(spec.stopOnAppQuit)
    }

    func testProbeKeepsPayload() throws {
        var config = AppConfig()
        config.services = [
            ServiceDescriptor(
                name: "P",
                lifecycle: .observed,
                appearance: Appearance(iconSymbol: "x", accent: .gray),
                probes: [
                    .processPattern("hermes gateway run"),
                    .tcpPort(49886),
                    .jsonState(path: "/tmp/a.json", key: "state")
                ]
            )
        ]
        let data = try ConfigStore.encoder.encode(config)
        let decoded = try ConfigStore.decoder.decode(AppConfig.self, from: data)
        let probes = decoded.services[0].probes
        XCTAssertEqual(probes.count, 3)
        guard case .processPattern(let pattern) = probes[0] else {
            return XCTFail("期望 processPattern")
        }
        XCTAssertEqual(pattern, "hermes gateway run")
        guard case .tcpPort(let port) = probes[1] else {
            return XCTFail("期望 tcpPort")
        }
        XCTAssertEqual(port, 49886)
        guard case .jsonState(let path, let key) = probes[2] else {
            return XCTFail("期望 jsonState")
        }
        XCTAssertEqual(path, "/tmp/a.json")
        XCTAssertEqual(key, "state")
    }

    func testParticipatesInAutoStartOnlyForManaged() {
        let observed = ServiceDescriptor(
            name: "O",
            lifecycle: .observed,
            autoStart: true,
            appearance: Appearance(iconSymbol: "x", accent: .gray)
        )
        let managed = ServiceDescriptor(
            name: "M",
            lifecycle: .managed,
            autoStart: true,
            appearance: Appearance(iconSymbol: "x", accent: .gray),
            managed: .process(ProcessSpec(executable: "/bin/true"))
        )
        let disabled = ServiceDescriptor(
            name: "D",
            lifecycle: .managed,
            enabled: false,
            autoStart: true,
            appearance: Appearance(iconSymbol: "x", accent: .gray),
            managed: .process(ProcessSpec(executable: "/bin/true"))
        )
        XCTAssertFalse(observed.participatesInAutoStart)
        XCTAssertTrue(managed.participatesInAutoStart)
        XCTAssertFalse(disabled.participatesInAutoStart)
    }
}
