import XCTest
@testable import AiServiceHubCore

/// 针对本机真实状态的探测验证
///
/// 这些用例依赖宿主机上实际运行的服务；不存在时自动跳过，
/// 因此不会影响没有 Hermes / DSH 的环境（例如 CI）。
final class LiveProbeTests: XCTestCase {
    func testHermesGatewayParsingAgainstRealState() async throws {
        let path = HermesPreset.defaultHome() + "/gateway_state.json"
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: path),
            "本机没有 Hermes Gateway 状态文件"
        )

        let result = await ProbeEvaluator().evaluate(.hermesGateway(path: path))

        XCTAssertEqual(result.label, "Gateway")
        XCTAssertEqual(result.state, .ok, "Gateway 应当处于 running：\(result.summary)")
        XCTAssertEqual(result.summary, "running")

        let runtime = try XCTUnwrap(result.groups.first { $0.title == "运行时" })
        XCTAssertTrue(runtime.rows.contains { $0.label == "PID" })
        XCTAssertTrue(runtime.rows.contains { $0.label == "活跃 Agent" })
        // Gateway 端口是动态分配的，必须能按 pid 反查出来
        let portRow = try XCTUnwrap(runtime.rows.first { $0.label == "监听端口" })
        XCTAssertNotEqual(portRow.value, "—", "应当能反查到 Gateway 的监听端口")

        let platforms = try XCTUnwrap(result.groups.first { $0.title == "消息平台" })
        XCTAssertTrue(platforms.rows.contains { $0.label == "qqbot" })
    }

    func testHermesPresetBuildsExpectedDescriptor() {
        let descriptor = HermesPreset.makeDescriptor()
        XCTAssertEqual(descriptor.lifecycle, .observed, "Hermes 必须是纯监控")
        XCTAssertNil(descriptor.managed, "纯监控服务不应有 managed 配置")
        XCTAssertFalse(descriptor.participatesInAutoStart)
        XCTAssertEqual(descriptor.presetIdentifier, HermesPreset.identifier)
        XCTAssertTrue(descriptor.logSources.contains { $0.id == "hermes-gateway" })
    }

    func testDSHWebProcessAndPort() async throws {
        let inspector = ProcessInspector()
        let processes = await inspector.allProcesses(matching: ["dsh web"])
        try XCTSkipUnless(!processes.isEmpty, "本机没有运行 dsh web")

        let first = try XCTUnwrap(processes.first)
        let ports = await inspector.listeningPorts(pid: first.pid)
        XCTAssertTrue(ports.contains(3080), "dsh web 应当监听 3080，实际：\(ports)")
    }

    func testDSHPresetBuildsExpectedDescriptor() {
        let descriptor = DSHPreset.makeDescriptor()
        XCTAssertEqual(descriptor.lifecycle, .observed)
        XCTAssertNil(descriptor.managed)
        XCTAssertEqual(descriptor.presetIdentifier, DSHPreset.identifier)
        // DSH 没有免鉴权健康端点，探测语义是「可达」
        XCTAssertTrue(descriptor.probes.contains { probe in
            if case .httpReachability = probe { return true }
            return false
        })
    }

    func testAstrBotPresetIsManagedProcess() {
        let descriptor = AstrBotPreset.makeDescriptor()
        XCTAssertEqual(descriptor.lifecycle, .managed)
        XCTAssertEqual(descriptor.driver, .process)
        XCTAssertTrue(descriptor.autoStart)
        XCTAssertEqual(descriptor.presetIdentifier, AstrBotPreset.identifier)
        guard case .process(let spec) = descriptor.managed else {
            return XCTFail("期望 process 子类型")
        }
        XCTAssertTrue(spec.ownership.detached, "AstrBot 应当 daemon 化")
        XCTAssertFalse(spec.ownership.stopOnAppQuit)
        // cwd 是数据目录的父目录
        XCTAssertEqual(spec.workingDirectory, NSHomeDirectory())
    }
}
