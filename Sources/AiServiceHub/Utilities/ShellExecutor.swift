import Foundation

/// Shell 命令执行器（async / awaiting / streamable）
struct ShellExecutor {
    /// 同步执行结果
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var success: Bool { exitCode == 0 }
    }

    /// 异步执行命令
    /// - Parameters:
    ///   - executable: 可执行文件路径或命令名（PATH 中查找）
    ///   - arguments: 参数列表
    ///   - environment: 额外环境变量
    ///   - workingDirectory: 工作目录
    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = runSync(
                    executable,
                    arguments: arguments,
                    environment: environment,
                    workingDirectory: workingDirectory
                )
                continuation.resume(returning: result)
            }
        }
    }

    /// 同步版本
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
            for (k, v) in environment { env[k] = v }
            process.environment = env
        }

        do {
            try process.run()
        } catch {
            AppLog.error("Failed to launch \(executable): \(error.localizedDescription)")
            return Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// 缓存 which() 结果（每 60s 失效），避免每次调用都解析 shell 配置
    nonisolated(unsafe) private static var whichCache: [String: (path: String, timestamp: Date)] = [:]
    nonisolated(unsafe) static var dockerAvailableCache: (available: Bool, timestamp: Date)?
    private static let whichCacheTTL: TimeInterval = 60

    /// 在 PATH 中查找可执行文件
    /// 1. 优先查找标准 PATH（GUI app 通常只能看到系统 PATH）
    /// 2. 解析用户 shell 配置（~/.zshrc / ~/.zprofile）中的 PATH
    /// 3. 常见安装位置兜底（Homebrew Apple Silicon/Intel、用户本地 bin）
    /// 结果缓存 60s
    static func which(_ command: String) -> String? {
        // 命中缓存
        if let entry = whichCache[command] {
            if Date().timeIntervalSince(entry.timestamp) < whichCacheTTL {
                return entry.path
            }
        }

        let result = whichUncached(command)

        // 缓存（含 nil 也缓存，避免每次都扫完整 PATH）
        whichCache[command] = (result ?? "", Date())
        return result
    }

    private static func whichUncached(_ command: String) -> String? {
        // 1. 标准 PATH
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        if let found = findInPath(command, pathString: envPath) {
            return found
        }

        // 2. 解析用户 shell 配置
        let userPath = extractUserShellPath()
        if !userPath.isEmpty, let found = findInPath(command, pathString: userPath) {
            return found
        }

        // 3. 常见安装位置兜底
        let home = NSHomeDirectory()
        let fallbacks = [
            "/opt/homebrew/bin/\(command)",   // Apple Silicon Homebrew
            "/usr/local/bin/\(command)",       // Intel Homebrew
            "\(home)/.local/bin/\(command)",   // uv tool / pipx
            "\(home)/.cargo/bin/\(command)",   // cargo
            "\(home)/.npm-global/bin/\(command)", // npm global
            "\(home)/.bun/bin/\(command)"      // bun
        ]
        for candidate in fallbacks {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 在冒号分隔的 PATH 字符串中查找命令
    private static func findInPath(_ command: String, pathString: String) -> String? {
        let dirs = pathString.split(separator: ":").map(String.init)
        for dir in dirs where !dir.isEmpty {
            let candidate = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 从用户 shell 配置中提取 PATH
    /// 读取 ~/.zshrc / ~/.zprofile / ~/.zshenv / ~/.bash_profile / ~/.bashrc
    private static func extractUserShellPath() -> String {
        let home = NSHomeDirectory()
        let shellFiles = [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc"]
        var collectedPaths: [String] = []
        var seen = Set<String>()

        for file in shellFiles {
            let path = "\(home)/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // 跳过注释
                if trimmed.hasPrefix("#") { continue }

                // 匹配 PATH= 或 export PATH=
                let prefix: String
                if trimmed.hasPrefix("export PATH=") {
                    prefix = "export PATH="
                } else if trimmed.hasPrefix("PATH=") {
                    prefix = "PATH="
                } else {
                    continue
                }

                var value = String(trimmed.dropFirst(prefix.count))
                // 去除引号
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                // 展开 $PATH 引用
                let expanded = value.replacingOccurrences(of: "$PATH", with: collectedPaths.joined(separator: ":"))
                let parts = expanded.split(separator: ":").map(String.init)
                for part in parts where !part.isEmpty {
                    let expandedPart = (part as NSString).expandingTildeInPath
                    if seen.insert(expandedPart).inserted {
                        collectedPaths.append(expandedPart)
                    }
                }
            }
        }

        return collectedPaths.joined(separator: ":")
    }

    /// 检查文件是否存在
    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
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
