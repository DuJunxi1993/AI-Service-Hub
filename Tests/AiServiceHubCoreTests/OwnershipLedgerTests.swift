import XCTest
import Darwin
@testable import AiServiceHubCore

final class OwnershipLedgerTests: XCTestCase {
    private func makeRecord(pid: pid_t, detached: Bool) -> OwnedProcessRecord {
        OwnedProcessRecord(
            serviceID: UUID(),
            pid: pid,
            startTimeToken: ProcessInspector.startTimeToken(pid: pid),
            executable: "/bin/sleep",
            arguments: ["30"],
            detached: detached
        )
    }

    func testReclaimTerminatesNonDetachedOrphan() async throws {
        let pid = try XCTUnwrap(
            DaemonSpawner.spawn(executable: "/bin/sleep", arguments: ["30"], detached: false)
        )
        var records = [makeRecord(pid: pid, detached: false)]

        let terminated = await OwnershipLedger().reclaimOrphans(in: &records)

        XCTAssertEqual(terminated, [pid])
        XCTAssertTrue(records.isEmpty, "回收后账本应清空")
        XCTAssertFalse(ProcessInspector.isAlive(pid: pid), "非 detached 的孤儿应被终止")
    }

    func testReclaimKeepsDetachedProcessAlive() async throws {
        let pid = try XCTUnwrap(
            DaemonSpawner.spawn(executable: "/bin/sleep", arguments: ["30"], detached: true)
        )
        defer { kill(pid, SIGKILL) }

        var records = [makeRecord(pid: pid, detached: true)]

        let terminated = await OwnershipLedger().reclaimOrphans(in: &records)

        XCTAssertTrue(terminated.isEmpty, "daemon 化的进程不应被终止")
        XCTAssertTrue(records.isEmpty, "但要从账本里摘掉")
        XCTAssertTrue(ProcessInspector.isAlive(pid: pid), "进程应继续存活")
    }

    func testReclaimDropsRecordsForDeadProcesses() async {
        var records = [
            OwnedProcessRecord(
                serviceID: UUID(),
                pid: 999_999,
                startTimeToken: nil,
                executable: "/bin/sleep",
                arguments: [],
                detached: false
            )
        ]
        let terminated = await OwnershipLedger().reclaimOrphans(in: &records)
        XCTAssertTrue(terminated.isEmpty)
        XCTAssertTrue(records.isEmpty)
    }

    func testReclaimDoesNotKillRecycledPID() async throws {
        let pid = try XCTUnwrap(
            DaemonSpawner.spawn(executable: "/bin/sleep", arguments: ["30"], detached: false)
        )
        defer { kill(pid, SIGKILL) }

        // 账本里的启动时间与实际进程不符 → 说明 pid 已被复用，不能杀
        var records = [
            OwnedProcessRecord(
                serviceID: UUID(),
                pid: pid,
                startTimeToken: "0.0",
                executable: "/bin/sleep",
                arguments: [],
                detached: false
            )
        ]
        let terminated = await OwnershipLedger().reclaimOrphans(in: &records)
        XCTAssertTrue(terminated.isEmpty, "pid 被复用时不应误杀")
        XCTAssertTrue(ProcessInspector.isAlive(pid: pid))
    }

    func testUpsertAndRemove() {
        let ledger = OwnershipLedger()
        var config = AppConfig()
        let serviceID = UUID()
        let record = OwnedProcessRecord(
            serviceID: serviceID,
            pid: 123,
            startTimeToken: "1.2",
            executable: "/bin/true",
            arguments: [],
            detached: true
        )

        ledger.upsert(record, in: &config)
        XCTAssertEqual(ledger.record(for: serviceID, in: config)?.pid, 123)

        var updated = record
        updated.pid = 456
        ledger.upsert(updated, in: &config)
        XCTAssertEqual(config.ownedProcesses.count, 1, "同一服务应覆盖而不是追加")
        XCTAssertEqual(config.ownedProcesses.first?.pid, 456)

        ledger.remove(serviceID: serviceID, from: &config)
        XCTAssertTrue(config.ownedProcesses.isEmpty)
    }
}
