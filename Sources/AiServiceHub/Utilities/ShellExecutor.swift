import Foundation
import AiServiceHubCore

/// Shell 命令执行器（App 层薄封装，实际实现在 Core）
///
/// - 异步路径走 `CommandRunner`：stdout/stderr 并发读取、支持超时与取消。
/// - 同步路径仅保留给确实需要同步的短命令，同样并发读取两个管道，避免写满死锁。
struct ShellExecutor {
    /// 同步执行结果
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var success: Bool { exitCode == 0 }
    }

    /// 异步执行命令
    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) async throws -> Result {
        let result = try await CommandRunner().run(
            executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        return Result(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
    }

    /// 同步执行命令
    @discardableResult
    static func runSync(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) -> Result {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        if let environment {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment { env[key] = value }
            process.environment = env
        }

        // stdout / stderr 并发读取：子进程若先把 stderr 写满管道也不会死锁
        let group = DispatchGroup()
        let stdoutBox = DataBox()
        let stderrBox = DataBox()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            AppLog.error("Failed to launch \(executable): \(error.localizedDescription)")
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        group.wait()
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutBox.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.data, encoding: .utf8) ?? ""
        )
    }

    /// 在 PATH 中查找可执行文件（结果缓存 60s）
    static func which(_ command: String) -> String? {
        ExecutableLocator.shared.which(command)
    }

    /// 检查文件是否存在
    static func exists(_ path: String) -> Bool {
        PathExpander.exists(path)
    }

    /// 在指定目录下查找 compose 文件
    static func findComposeFile(in directory: String) -> String? {
        let fm = FileManager.default
        let candidates = ["compose.yml", "compose.yaml", "docker-compose.yml", "docker-compose.yaml"]
        for name in candidates {
            let path = "\(directory)/\(name)"
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}

/// 线程安全的数据容器
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
