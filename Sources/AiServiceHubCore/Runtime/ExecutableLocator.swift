import Foundation

/// 在 PATH 中定位可执行文件
///
/// GUI app 启动时继承的 PATH 通常只有系统路径，因此额外解析用户 shell 配置
/// （~/.zshrc 等）并回退到常见安装位置。
///
/// 缓存用锁保护（**未命中也缓存**，记为 nil），避免每次都扫完整 PATH。
public final class ExecutableLocator: @unchecked Sendable {
    public static let shared = ExecutableLocator()

    private struct Entry {
        let path: String?
        let timestamp: Date
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 60

    public init() {}

    /// 查找可执行文件，找不到返回 nil
    public func which(_ command: String) -> String? {
        lock.lock()
        if let entry = cache[command], Date().timeIntervalSince(entry.timestamp) < ttl {
            lock.unlock()
            return entry.path
        }
        lock.unlock()

        let resolved = whichUncached(command)

        lock.lock()
        cache[command] = Entry(path: resolved, timestamp: Date())
        lock.unlock()
        return resolved
    }

    /// 清空缓存
    public func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - 私有

    private func whichUncached(_ command: String) -> String? {
        // 1. 标准 PATH
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        if let found = findInPath(command, pathString: envPath) {
            return found
        }

        // 2. 用户 shell 配置里的 PATH
        let userPath = extractUserShellPath()
        if !userPath.isEmpty, let found = findInPath(command, pathString: userPath) {
            return found
        }

        // 3. 常见安装位置
        let home = NSHomeDirectory()
        let fallbacks = [
            "/opt/homebrew/bin/\(command)",        // Apple Silicon Homebrew
            "/usr/local/bin/\(command)",            // Intel Homebrew
            "\(home)/.local/bin/\(command)",        // uv tool / pipx
            "\(home)/.cargo/bin/\(command)",        // cargo
            "\(home)/.npm-global/bin/\(command)",   // npm global
            "\(home)/.bun/bin/\(command)"           // bun
        ]
        for candidate in fallbacks
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private func findInPath(_ command: String, pathString: String) -> String? {
        for dir in pathString.split(separator: ":").map(String.init) where !dir.isEmpty {
            let candidate = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 从用户 shell 配置中提取 PATH
    private func extractUserShellPath() -> String {
        let home = NSHomeDirectory()
        let shellFiles = [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc"]
        var collectedPaths: [String] = []
        var seen = Set<String>()

        for file in shellFiles {
            let path = "\(home)/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { continue }

                let prefix: String
                if trimmed.hasPrefix("export PATH=") {
                    prefix = "export PATH="
                } else if trimmed.hasPrefix("PATH=") {
                    prefix = "PATH="
                } else {
                    continue
                }

                var value = String(trimmed.dropFirst(prefix.count))
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                let expanded = value.replacingOccurrences(of: "$PATH", with: collectedPaths.joined(separator: ":"))
                for part in expanded.split(separator: ":").map(String.init) where !part.isEmpty {
                    let expandedPart = PathExpander.expand(part)
                    if seen.insert(expandedPart).inserted {
                        collectedPaths.append(expandedPart)
                    }
                }
            }
        }

        return collectedPaths.joined(separator: ":")
    }
}
