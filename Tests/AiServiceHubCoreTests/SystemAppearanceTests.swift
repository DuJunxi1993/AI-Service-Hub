import XCTest
@testable import AiServiceHubCore

final class SystemAppearanceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SystemAppearanceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// 深色模式下全局域有 AppleInterfaceStyle = "Dark"
    func testDetectsDarkMode() {
        defaults.set("Dark", forKey: SystemAppearance.appearanceKey)
        XCTAssertTrue(SystemAppearance.isDark(defaults: defaults))
    }

    /// 浅色模式下该键不存在 → 不是深色
    ///
    /// 注意：读 `AppleInterfaceStyle` 会回落到全局域，所以本机若处于深色模式，
    /// 自定义 suite 里删掉该键也仍会读到 "Dark"。
    /// 因此「键不存在」这一分支用纯函数单独验证。
    func testAbsentValueMeansLightMode() {
        XCTAssertFalse(SystemAppearance.isDarkValue(nil))
    }

    /// 只有 "Dark" 算深色
    func testOnlyExactDarkValueCounts() {
        XCTAssertTrue(SystemAppearance.isDarkValue("Dark"))
        XCTAssertFalse(SystemAppearance.isDarkValue("dark"))
        XCTAssertFalse(SystemAppearance.isDarkValue("Light"))
        XCTAssertFalse(SystemAppearance.isDarkValue(""))
    }

    /// 其它值不算深色
    func testIgnoresUnexpectedValues() {
        defaults.set("Light", forKey: SystemAppearance.appearanceKey)
        XCTAssertFalse(SystemAppearance.isDark(defaults: defaults))
        defaults.set("", forKey: SystemAppearance.appearanceKey)
        XCTAssertFalse(SystemAppearance.isDark(defaults: defaults))
    }
}
