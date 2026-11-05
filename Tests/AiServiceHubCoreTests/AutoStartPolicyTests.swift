import XCTest
@testable import AiServiceHubCore

/// 「启动时自动拉起」的生效策略
///
/// 自动拉起原本只在 app 启动时跑一次，用户在运行中勾选这个框看不到任何反应。
/// 勾选即生效：可管理的服务被新勾上时立刻拉起。
final class AutoStartPolicyTests: XCTestCase {
    private func makeDescriptor(
        autoStart: Bool,
        lifecycle: LifecycleMode = .managed
    ) -> ServiceDescriptor {
        ServiceDescriptor(
            name: "X",
            lifecycle: lifecycle,
            autoStart: autoStart,
            appearance: Appearance(iconSymbol: "x", accent: .gray)
        )
    }

    /// 新勾上 → 要立刻拉起
    func testEnablingAutoStartStartsImmediately() {
        let old = makeDescriptor(autoStart: false)
        var updated = old
        updated.autoStart = true
        XCTAssertTrue(updated.shouldStartImmediately(comparedTo: old))
    }

    /// 取消勾选 → 不拉起
    func testDisablingAutoStartDoesNotStart() {
        let old = makeDescriptor(autoStart: true)
        var updated = old
        updated.autoStart = false
        XCTAssertFalse(updated.shouldStartImmediately(comparedTo: old))
    }

    /// 本来就勾着（重复设置）→ 不拉起，避免重复启动
    func testAlreadyEnabledDoesNotStartAgain() {
        let old = makeDescriptor(autoStart: true)
        var updated = old
        updated.autoStart = true
        XCTAssertFalse(updated.shouldStartImmediately(comparedTo: old))
    }

    /// 纯监控服务不受本程序管理 → 不该被拉起
    func testObservedServiceIsNotStarted() {
        let old = makeDescriptor(autoStart: false, lifecycle: .observed)
        var updated = old
        updated.autoStart = true
        XCTAssertFalse(updated.shouldStartImmediately(comparedTo: old))
    }

    /// 可管理服务的 autoStart 参与自动拉起
    func testManagedServiceParticipatesInAutoStart() {
        let managed = makeDescriptor(autoStart: true, lifecycle: .managed)
        XCTAssertTrue(managed.participatesInAutoStart)

        let observed = makeDescriptor(autoStart: true, lifecycle: .observed)
        XCTAssertFalse(observed.participatesInAutoStart)
    }

    /// 被停用的服务不参与自动拉起
    func testDisabledServiceDoesNotParticipate() {
        var descriptor = makeDescriptor(autoStart: true, lifecycle: .managed)
        descriptor.enabled = false
        XCTAssertFalse(descriptor.participatesInAutoStart)
    }
}
