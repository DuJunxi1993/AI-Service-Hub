import Foundation

/// AstrBot 进程控制器
///
/// 使用 AstrBotProcessManager（posix_spawn daemon 化）来启动 AstrBot
/// - 启动后子进程脱离 app 进程组，被 launchd 接管
/// - app 关闭不影响 AstrBot 继续运行
/// - AstrBot 自己的日志写入 ~/data/logs/astrbot.log（与原来一致）
@MainActor
final class AstrBotController {
    private let processManager = AstrBotProcessManager()

    /// 检测 AstrBot 可执行文件路径
    /// 优先级: 1) PATH 中的 astrbot  2) uv tool 安装的 astrbot
    static func detectAstrbotPath() -> String? {
        // 1) PATH 中查找
        if let path = ShellExecutor.which("astrbot") {
            return path
        }
        // 2) uv tool 默认安装位置
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/astrbot",
            "/usr/local/bin/astrbot",
            "/opt/homebrew/bin/astrbot"
        ]
        for candidate in candidates {
            if ShellExecutor.exists(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 当前 AstrBot 进程是否在运行（pgrep 查询，不依赖 knownPID）
    var isRunning: Bool { processManager.isRunning() }

    /// AstrBot 当前 PID（优先 knownPID，否则 pgrep）
    var pid: Int32? { processManager.knownPID ?? processManager.currentPID() }

    /// 是否由本 app 启动
    var startedByUs: Bool { processManager.startedByUs }

    /// 当前已知 PID
    var knownPID: pid_t? { processManager.knownPID }

    /// 启动 AstrBot（daemon 化）
    /// - Parameters:
    ///   - onOutput: 不再使用（日志从 astrbot.log 文件读取）
    func start(onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard !isRunning else { return }
        _ = try processManager.start()
    }

    /// 停止 AstrBot（真正等待进程退出，由 processManager.stop() 处理 SIGTERM + 兜底 SIGKILL）
    func stop() async {
        await processManager.stop()
    }
}

/// 简单的 Shell 命令解析器
enum ShellParser {
    /// 将 "ls -la /tmp" 解析为 ("/bin/ls", ["-la", "/tmp"])
    static func parse(_ command: String) -> (executable: String, arguments: [String]) {
        var tokens: [String] = []
        var current = ""
        var quote: Character? = nil
        var iterator = command.makeIterator()

        while let c = iterator.next() {
            if let q = quote {
                if c == q {
                    quote = nil
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" || c == "'" {
                    quote = c
                } else if c == " " || c == "\t" {
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                } else {
                    current.append(c)
                }
            }
        }
        if !current.isEmpty { tokens.append(current) }

        guard let first = tokens.first else {
            return ("/bin/echo", [])
        }

        // 第一个 token 解析为可执行文件
        let executable: String
        if first.hasPrefix("/") || first.hasPrefix("~") {
            executable = (first as NSString).expandingTildeInPath
        } else if let resolved = ShellExecutor.which(first) {
            executable = resolved
        } else {
            executable = first
        }

        return (executable, Array(tokens.dropFirst()))
    }
}
