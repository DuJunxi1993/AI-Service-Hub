import XCTest
@testable import AiServiceHubCore

final class CommandRunnerTests: XCTestCase {
    func testCapturesStdout() async throws {
        let result = try await CommandRunner().run("/bin/echo", arguments: ["hello", "world"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
    }

    func testCapturesStderr() async throws {
        let result = try await CommandRunner().run("/bin/sh", arguments: ["-c", "echo oops 1>&2"])
        XCTAssertTrue(result.stderr.contains("oops"))
    }

    func testCapturesExitCode() async throws {
        let result = try await CommandRunner().run("/bin/sh", arguments: ["-c", "exit 3"])
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertFalse(result.success)
    }

    func testHandlesLargeStderrWithoutDeadlock() async throws {
        // stderr 超过管道缓冲区（旧实现会在这里死锁）
        let result = try await CommandRunner().run(
            "/bin/sh",
            arguments: ["-c", "yes '0123456789abcdef' | head -c 200000 1>&2"],
            timeout: .seconds(20)
        )
        XCTAssertGreaterThan(result.stderr.count, 100_000)
    }

    func testTimeoutThrows() async {
        do {
            _ = try await CommandRunner().run(
                "/bin/sh",
                arguments: ["-c", "sleep 10"],
                timeout: .milliseconds(300)
            )
            XCTFail("应当超时")
        } catch let error as CommandError {
            guard case .timedOut = error else {
                return XCTFail("期望 timedOut，实际 \(error)")
            }
        } catch {
            XCTFail("期望 CommandError，实际 \(error)")
        }
    }

    func testLaunchFailureThrows() async {
        do {
            _ = try await CommandRunner().run("/definitely/not/here")
            XCTFail("应当失败")
        } catch let error as CommandError {
            guard case .launchFailed = error else {
                return XCTFail("期望 launchFailed，实际 \(error)")
            }
        } catch {
            XCTFail("期望 CommandError，实际 \(error)")
        }
    }

    func testWorkingDirectoryIsHonoured() async throws {
        let result = try await CommandRunner().run(
            "/bin/pwd",
            workingDirectory: "/tmp"
        )
        // /tmp 在 macOS 上是 /private/tmp 的符号链接，两种结果都算正确
        let directory = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(["/tmp", "/private/tmp"].contains(directory), "实际工作目录：\(directory)")
    }

    func testEnvironmentIsMerged() async throws {
        let result = try await CommandRunner().run(
            "/bin/sh",
            arguments: ["-c", "echo $HUB_TEST_VAR"],
            environment: ["HUB_TEST_VAR": "hello-env"]
        )
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello-env")
    }
}
