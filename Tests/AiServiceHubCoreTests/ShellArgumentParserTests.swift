import XCTest
@testable import AiServiceHubCore

final class ShellArgumentParserTests: XCTestCase {
    func testParseSimpleCommand() {
        let result = ShellArgumentParser.parse("ls -la /tmp")
        XCTAssertEqual(result.executable, "ls")
        XCTAssertEqual(result.arguments, ["-la", "/tmp"])
    }

    func testParseKeepsQuotedArgumentsTogether() {
        let result = ShellArgumentParser.parse("astrbot run --config \"/Users/me/my config.yaml\"")
        XCTAssertEqual(result.executable, "astrbot")
        XCTAssertEqual(result.arguments, ["run", "--config", "/Users/me/my config.yaml"])
    }

    func testParseSingleQuotes() {
        let result = ShellArgumentParser.parse("echo 'hello world'")
        XCTAssertEqual(result.executable, "echo")
        XCTAssertEqual(result.arguments, ["hello world"])
    }

    func testParseEmptyCommand() {
        let result = ShellArgumentParser.parse("")
        XCTAssertEqual(result.executable, "/bin/echo")
        XCTAssertTrue(result.arguments.isEmpty)
    }

    // MARK: - shell 语法检测

    func testRequiresShellDetectsAndOperator() {
        XCTAssertNotNil(ShellArgumentParser.requiresShell("cd /path && uv run astrbot run"))
    }

    func testRequiresShellDetectsPipe() {
        XCTAssertNotNil(ShellArgumentParser.requiresShell("astrbot run | tee log.txt"))
    }

    func testRequiresShellDetectsRedirection() {
        XCTAssertNotNil(ShellArgumentParser.requiresShell("astrbot run > out.log"))
    }

    func testRequiresShellDetectsCommandSubstitution() {
        XCTAssertNotNil(ShellArgumentParser.requiresShell("echo $(whoami)"))
    }

    func testRequiresShellAllowsPlainCommand() {
        XCTAssertNil(ShellArgumentParser.requiresShell("astrbot run"))
    }

    func testRequiresShellAllowsQuotedPath() {
        XCTAssertNil(ShellArgumentParser.requiresShell("\"/Users/me/my app/astrbot\" run"))
    }
}
