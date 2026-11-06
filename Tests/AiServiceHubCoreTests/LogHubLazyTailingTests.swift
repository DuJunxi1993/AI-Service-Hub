import XCTest
@testable import AiServiceHubCore

/// 收集日志行的 actor（测试用）
private actor LineCollector {
    private var storage: [String] = []
    func add(_ lines: [String]) { storage.append(contentsOf: lines) }
    var all: [String] { storage }
}

/// 日志跟随的惰性化
///
/// 本程序本质上是个**查看器**：日志只有在用户打开日志面板时才有意义。
/// 没有订阅者时不该在后台每秒 stat 文件、每两秒起一个 docker 进程。
final class LogHubLazyTailingTests: XCTestCase {

    private func makeDescriptor(logPath: String) -> ServiceDescriptor {
        ServiceDescriptor(
            id: UUID(),
            name: "测试服务",
            lifecycle: .observed,
            appearance: Appearance(iconSymbol: "gearshape", accent: RGBAColor(red: 0.2, green: 0.4, blue: 0.8)),
            logSources: [.file(id: "t", label: "测试日志", path: logPath)]
        )
    }

    private func makeTempLog(contents: String) -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("lazy-\(UUID().uuidString).log").path
        FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
        return path
    }

    /// attach 只登记来源，**不**开始跟随
    func testAttachDoesNotStartTailing() async throws {
        let path = makeTempLog(contents: "hello\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let hub = LogHub()
        let descriptor = makeDescriptor(logPath: path)
        await hub.attach(descriptor: descriptor)

        // 没有订阅者 → 不应该有日志进来
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let history = await hub.history(serviceID: descriptor.id)
        XCTAssertTrue(history.isEmpty, "没有订阅者时不应该有日志行")
    }

    /// 订阅后开始跟随，历史会顺着流推下来
    func testSubscribeStartsTailingAndDeliversHistory() async throws {
        let path = makeTempLog(contents: "first line\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let hub = LogHub()
        let descriptor = makeDescriptor(logPath: path)
        await hub.attach(descriptor: descriptor)

        let collector = LineCollector()
        let stream = await hub.subscribe(serviceID: descriptor.id)
        let task = Task {
            for await batch in stream {
                await collector.add(batch.map(\.content))
            }
        }

        // 跟随器首次轮询会把历史推下来
        try await Task.sleep(nanoseconds: 2_000_000_000)
        task.cancel()

        let lines = await collector.all
        XCTAssertTrue(lines.contains("first line"), "订阅后应该收到历史，实际收到：\(lines)")
    }

    /// 订阅结束 → 停止跟随（后台不再空转）
    func testUnsubscribeStopsTailing() async throws {
        let path = makeTempLog(contents: "x\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let hub = LogHub()
        let descriptor = makeDescriptor(logPath: path)
        await hub.attach(descriptor: descriptor)

        do {
            let stream = await hub.subscribe(serviceID: descriptor.id)
            let task = Task {
                for await _ in stream { }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            task.cancel()
        }

        // 取消订阅后，缓冲会被清掉（跟随停止）
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let history = await hub.history(serviceID: descriptor.id)
        XCTAssertTrue(history.isEmpty, "订阅结束后不应继续保留缓冲")
    }
}
