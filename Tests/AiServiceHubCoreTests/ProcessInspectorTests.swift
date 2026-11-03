import XCTest
@testable import AiServiceHubCore

final class ProcessInspectorTests: XCTestCase {
    func testParseProcessTable() {
        let output = """
          30228 /Users/me/.hermes/bin/hermes gateway run
          47228 node /Users/djx/.npm-global/bin/dsh web --port 3080
        """
        let table = ProcessTable.parse(output)
        XCTAssertEqual(table.entries.count, 2)
        XCTAssertEqual(table.entries[0].pid, 30228)
        XCTAssertEqual(table.entries[1].pid, 47228)
        XCTAssertTrue(table.entries[1].command.contains("dsh web"))
    }

    func testProcessTableMatching() {
        let table = ProcessTable.parse("""
          1 /usr/bin/hermes gateway run
          2 node /x/dsh web --port 3080
          3 /bin/zsh
        """)
        XCTAssertEqual(table.matching(["dsh web"]).map(\.pid), [2])
        XCTAssertEqual(table.matching(["hermes gateway"]).map(\.pid), [1])
        XCTAssertTrue(table.matching([]).isEmpty)
        XCTAssertTrue(table.matching(["nothing-matches"]).isEmpty)
    }

    func testParseProcessTableIgnoresGarbage() {
        XCTAssertTrue(ProcessTable.parse("").entries.isEmpty)
        XCTAssertTrue(ProcessTable.parse("no-pid-here").entries.isEmpty)
    }

    func testParseListeningPorts() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    47228 djx   14u  IPv4  0x1  0t0  TCP 127.0.0.1:3080 (LISTEN)
        node    47228 djx   16u  IPv4  0x2  0t0  TCP 127.0.0.1:55708 (LISTEN)
        """
        let ports = ProcessInspector.parseListeningPorts(output)
        XCTAssertEqual(ports, [3080, 55708])
    }

    func testParseListeningPortsIgnoresEstablishedConnections() {
        let output = """
        node    47228 djx   14u  IPv4  0x1  0t0  TCP 127.0.0.1:3080 (ESTABLISHED)
        """
        XCTAssertTrue(ProcessInspector.parseListeningPorts(output).isEmpty)
    }

    func testIsAliveRejectsInvalidPID() {
        XCTAssertFalse(ProcessInspector.isAlive(pid: 0))
        XCTAssertFalse(ProcessInspector.isAlive(pid: -1))
    }

    func testStartTimeTokenIsStableForSameProcess() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let token = ProcessInspector.startTimeToken(pid: pid)
        XCTAssertNotNil(token)
        XCTAssertEqual(token, ProcessInspector.startTimeToken(pid: pid))
    }

    func testMatchesIdentityRejectsDifferentStartTime() {
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(ProcessInspector.matchesIdentity(pid: pid, startTimeToken: nil))
        XCTAssertFalse(ProcessInspector.matchesIdentity(pid: pid, startTimeToken: "0.0"))
    }
}

final class ProbeEvaluatorTests: XCTestCase {
    func testFlattenJSON() {
        let object: [String: Any] = [
            "gateway_state": "running",
            "session_store": ["status": "ok"],
            "platforms": ["qqbot": ["state": "connected"]]
        ]
        let flat = ProbeEvaluator.flattenJSON(object)
        XCTAssertEqual(flat["gateway_state"] as? String, "running")
        XCTAssertEqual(flat["session_store.status"] as? String, "ok")
        XCTAssertEqual(flat["platforms.qqbot.state"] as? String, "connected")
    }

    func testStaleTimestampDetection() {
        let fresh = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        XCTAssertFalse(ProbeEvaluator.isStale(fresh))

        let old = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200))
        XCTAssertTrue(ProbeEvaluator.isStale(old))
    }

    func testStaleTimestampIgnoresGarbage() {
        XCTAssertFalse(ProbeEvaluator.isStale("not-a-date"))
    }
}
