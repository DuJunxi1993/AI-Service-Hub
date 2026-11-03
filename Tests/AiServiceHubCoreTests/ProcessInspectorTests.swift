import XCTest
@testable import AiServiceHubCore

final class ProcessInspectorTests: XCTestCase {
    func testParsePgrepLine() {
        let snapshot = ProcessInspector.parsePgrepLine("30228 4:41:00 /Users/me/.hermes/bin/hermes gateway run")
        XCTAssertEqual(snapshot?.pid, 30228)
        XCTAssertEqual(snapshot?.elapsed, "4:41:00")
        XCTAssertEqual(snapshot?.command, "/Users/me/.hermes/bin/hermes gateway run")
    }

    func testParsePgrepLineIgnoresPgrepItself() {
        XCTAssertNil(ProcessInspector.parsePgrepLine("123 1:00 /usr/bin/pgrep -fl astrbot"))
    }

    func testParsePgrepLineIgnoresGarbage() {
        XCTAssertNil(ProcessInspector.parsePgrepLine(""))
        XCTAssertNil(ProcessInspector.parsePgrepLine("no-pid-here"))
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
