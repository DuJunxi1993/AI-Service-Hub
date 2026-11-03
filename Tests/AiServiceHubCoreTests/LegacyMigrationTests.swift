import XCTest
@testable import AiServiceHubCore

final class LegacyMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.legacy.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testMigratesAstrBotIntoManagedProcessService() {
        defaults.set("uvToolRun", forKey: "astrBotLaunchMode")
        defaults.set(6185, forKey: "astrBotWebPort")
        defaults.set("/Users/me/data", forKey: "dataDirectory")
        defaults.set("/Users/me/data/logs/astrbot.log", forKey: "astrbotLogPath")

        let config = LegacyMigration.migrate(defaults: defaults)

        let astrBot = config.services.first { $0.name == "AstrBot" }
        XCTAssertNotNil(astrBot)
        XCTAssertEqual(astrBot?.lifecycle, .managed)
        XCTAssertEqual(astrBot?.driver, .process)
        guard case .process(let spec) = astrBot?.managed else {
            return XCTFail("期望 process 子类型")
        }
        XCTAssertEqual(spec.arguments, ["run"])
        XCTAssertEqual(spec.workingDirectory, "/Users/me")
        XCTAssertTrue(spec.ownership.detached)
        XCTAssertFalse(spec.ownership.stopOnAppQuit)
    }

    func testMigratesContainersIntoManagedContainerServices() {
        defaults.set("napcat-napcat-1", forKey: "napcatContainer")
        defaults.set("shipyard-shipyard-1", forKey: "shipyardContainer")

        let config = LegacyMigration.migrate(defaults: defaults)

        let napcat = config.services.first { $0.name == "NapCat" }
        XCTAssertEqual(napcat?.lifecycle, .managed)
        XCTAssertEqual(napcat?.driver, .container)
        guard case .container(let spec) = napcat?.managed else {
            return XCTFail("期望 container 子类型")
        }
        XCTAssertEqual(spec.containerName, "napcat-napcat-1")
        XCTAssertTrue(spec.stopOnAppQuit)
    }

    func testSkipsEmptyContainerNames() {
        defaults.set("", forKey: "napcatContainer")
        let config = LegacyMigration.migrate(defaults: defaults)
        XCTAssertNil(config.services.first { $0.name == "NapCat" })
    }

    func testMigratesCustomCommandWithShellSyntax() {
        defaults.set("customCommand", forKey: "astrBotLaunchMode")
        defaults.set("cd /Users/me && uv run astrbot run", forKey: "astrBotCustomCommand")

        let config = LegacyMigration.migrate(defaults: defaults)
        let astrBot = config.services.first { $0.name == "AstrBot" }
        guard case .process(let spec) = astrBot?.managed else {
            return XCTFail("期望 process 子类型")
        }
        // 含 shell 语法 → 迁移后必须走 shell 模式，否则命令跑不通
        XCTAssertTrue(spec.shellMode)
    }

    func testMigratesPreferences() {
        defaults.set(12, forKey: "pollingInterval")
        defaults.set("dark", forKey: "themeMode")
        defaults.set(true, forKey: "startMinimized")
        defaults.set(false, forKey: "autoStartAllServices")

        let config = LegacyMigration.migrate(defaults: defaults)
        XCTAssertEqual(config.preferences.pollingIntervalSeconds, 12)
        XCTAssertEqual(config.preferences.themeMode, .dark)
        XCTAssertTrue(config.preferences.startMinimized)
        XCTAssertFalse(config.preferences.autoStartAllServices)
    }

    func testMigrationDoesNotWriteBackToLegacyDomain() {
        defaults.set("uvToolRun", forKey: "astrBotLaunchMode")
        let before = defaults.dictionaryRepresentation()

        _ = LegacyMigration.migrate(defaults: defaults)

        let after = defaults.dictionaryRepresentation()
        XCTAssertEqual(after.count, before.count)
        for (key, value) in before {
            XCTAssertEqual(after[key] as? NSObject, value as? NSObject)
        }
    }

    func testHasLegacyDataDetectsEmptyDomain() {
        XCTAssertFalse(LegacyMigration.hasLegacyData(defaults: defaults))
        defaults.set("uvToolRun", forKey: "astrBotLaunchMode")
        XCTAssertTrue(LegacyMigration.hasLegacyData(defaults: defaults))
    }
}
