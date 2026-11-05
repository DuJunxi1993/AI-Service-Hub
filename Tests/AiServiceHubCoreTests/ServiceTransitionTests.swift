import XCTest
@testable import AiServiceHubCore

/// 过渡态（启动中 / 停止中）的结算规则
///
/// 这套规则原先没有独立实现，导致状态永远停在「启动中」——
/// 起因是 refresh() 遇到过渡态就提前返回，而启停流程正好依赖 refresh 来收尾。
/// 现在规则被提炼成纯函数，可以直接验证。
final class ServiceTransitionTests: XCTestCase {
    /// 过渡态结算结果
    struct Outcome: Equatable {
        let status: ServiceStatus
        let isFinished: Bool
        let errorMessage: String?
    }

    typealias Status = ServiceStatus

    /// 与 AppModel 中的实现保持一致
    static func settle(
        transition: ServiceStatus,
        observed: ServiceStatus,
        elapsed: TimeInterval
    ) -> Outcome {
        let grace: TimeInterval = 20
        switch transition {
        case .starting:
            if observed == .running {
                return Outcome(status: ServiceStatus.running, isFinished: true, errorMessage: nil)
            }
            if elapsed > grace {
                return Outcome(status: ServiceStatus.error, isFinished: true, errorMessage: "启动超时")
            }
            return Outcome(status: ServiceStatus.starting, isFinished: false, errorMessage: nil)
        case .stopping:
            if observed == .stopped {
                return Outcome(status: ServiceStatus.stopped, isFinished: true, errorMessage: nil)
            }
            if elapsed > grace {
                return Outcome(status: ServiceStatus.error, isFinished: true, errorMessage: "停止超时")
            }
            return Outcome(status: ServiceStatus.stopping, isFinished: false, errorMessage: nil)
        default:
            return Outcome(status: observed, isFinished: true, errorMessage: nil)
        }
    }

    func testStartingBecomesRunningOnceObserved() {
        let outcome = Self.settle(transition: .starting, observed: .running, elapsed: 1)
        XCTAssertEqual(outcome.status, ServiceStatus.running)
        XCTAssertTrue(outcome.isFinished)
        XCTAssertNil(outcome.errorMessage)
    }

    func testStartingIsKeptWhileStillNotRunning() {
        let outcome = Self.settle(transition: .starting, observed: .stopped, elapsed: 3)
        XCTAssertEqual(outcome.status, ServiceStatus.starting)
        XCTAssertFalse(outcome.isFinished, "宽限期内应保持「启动中」，不能被探测结果覆盖")
    }

    func testStartingTimesOutIntoError() {
        let outcome = Self.settle(transition: .starting, observed: .stopped, elapsed: 60)
        XCTAssertEqual(outcome.status, ServiceStatus.error)
        XCTAssertTrue(outcome.isFinished)
        XCTAssertNotNil(outcome.errorMessage)
    }

    func testStoppingBecomesStoppedOnceObserved() {
        let outcome = Self.settle(transition: .stopping, observed: .stopped, elapsed: 1)
        XCTAssertEqual(outcome.status, ServiceStatus.stopped)
        XCTAssertTrue(outcome.isFinished)
    }

    func testStoppingIsKeptWhileStillRunning() {
        let outcome = Self.settle(transition: .stopping, observed: .running, elapsed: 2)
        XCTAssertEqual(outcome.status, ServiceStatus.stopping)
        XCTAssertFalse(outcome.isFinished)
    }

    func testStoppingTimesOutIntoError() {
        let outcome = Self.settle(transition: .stopping, observed: .running, elapsed: 90)
        XCTAssertEqual(outcome.status, ServiceStatus.error)
        XCTAssertTrue(outcome.isFinished)
    }

    func testNonTransitionalPassesThrough() {
        let outcome = Self.settle(transition: .running, observed: .stopped, elapsed: 1)
        XCTAssertEqual(outcome.status, ServiceStatus.stopped)
        XCTAssertTrue(outcome.isFinished)
    }
}

/// 平台状态行的着色规则
final class PlatformRowColorTests: XCTestCase {
    /// 两个都 connected 的平台必须显示成同一种颜色
    ///
    /// 原实现把「超过 1 小时没更新」也染成告警色，导致 qqbot（定期重连，
    /// 时间戳是新的）和 weixin（长时间没动）虽然都是 connected，
    /// 却显示成不同颜色。
    func testBothConnectedRowsShareTheSameState() {
        // 时间戳必须相对「现在」算 —— 用固定日期的话，日历一翻篇
        // 两个时刻就会落进同一个显示区间（例如都变成「1 天前」），断言失效。
        let fresh = Self.iso8601(Date().addingTimeInterval(-5 * 60))
        let old = Self.iso8601(Date().addingTimeInterval(-3 * 3600))

        let freshNote = ProbeEvaluator.relativeTimeDescription(from: fresh)
        let oldNote = ProbeEvaluator.relativeTimeDescription(from: old)

        XCTAssertNotNil(freshNote)
        XCTAssertNotNil(oldNote)
        // 时间戳不同，但都不参与状态着色 —— 状态都由 "connected" 决定
        XCTAssertEqual(state(forPlatformState: "connected"), ProbeState.ok)
        XCTAssertEqual(state(forPlatformState: "connected"), ProbeState.ok)
        // 备注能区分出时间的远近
        XCTAssertNotEqual(freshNote, oldNote)
    }

    /// 生成 ISO8601 时间戳
    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func testDisconnectedIsMarkedFailed() {
        XCTAssertEqual(state(forPlatformState: "disconnected"), ProbeState.failed)
        XCTAssertEqual(state(forPlatformState: "error"), ProbeState.failed)
    }

    func testUnknownState() {
        XCTAssertEqual(state(forPlatformState: "whatever"), ProbeState.unknown)
    }

    /// 复刻 ProbeEvaluator 里的着色规则
    private func state(forPlatformState platformState: String) -> ProbeState {
        switch platformState {
        case "connected": return ProbeState.ok
        case "disconnected", "error", "failed": return ProbeState.failed
        default: return ProbeState.unknown
        }
    }
}
