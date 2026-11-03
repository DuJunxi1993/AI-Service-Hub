import Foundation

/// AstrBot 进程生命周期管理器
///
/// 职责：
/// - 启动 AstrBot（daemon 化，子进程脱离 app 进程组）
/// - 停止 AstrBot（先 SIGTERM，5 秒后 SIGKILL）
/// - 查询 AstrBot 状态（pgrep）
/// - 检测孤儿 AstrBot 实例并清理
@MainActor
final class AstrBotProcessManager {
    /// 已知 PID（最近一次本 app 启动的 AstrBot）
    private(set) var knownPID: pid_t?

    /// 是否由本 app 启动
    private(set) var startedByUs: Bool = false

    /// 启动 AstrBot（daemon 化）
    @discardableResult
    func start() throws -> pid_t {
        // 1. 先清理孤儿实例
        try? cleanupOrphans()

        // 2. 构建启动命令
        let settings = AppSettings.shared
        let mode = settings.astrBotLaunchMode
        let (executable, args) = try buildLaunchCommand(mode: mode, settings: settings)
        AppLog.info("AstrBot start: executable=\(executable) args=\(args)")

        // 3. 工作目录：AstrBot 期望在 data 目录的**父目录**运行
        //    （即 <project_root>，data/ 在它下面）
        let dataDir = (settings.dataDirectory as NSString).expandingTildeInPath
        let parent = (dataDir as NSString).deletingLastPathComponent
        let workingDirectory: String? = FileManager.default.fileExists(atPath: parent) ? parent : nil
        AppLog.info("AstrBot start: dataDir=\(dataDir) cwd=\(workingDirectory ?? "inherit")")

        // 4. spawn daemon
        guard let pid = ProcessSpawner.spawnDaemon(
            executable: executable,
            arguments: args,
            workingDirectory: workingDirectory
        ) else {
            throw NSError(
                domain: "AstrBotProcessManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法启动 AstrBot"]
            )
        }

        knownPID = pid
        startedByUs = true
        AppLog.info("AstrBot started: pid=\(pid)")
        return pid
    }

    /// 停止 AstrBot（真正等待进程退出）
    /// - SIGTERM → 等 5s（让 daemon 优雅退出）
    /// - 兜底 SIGKILL → 再等 1s
    /// - 进程确认死后才清 `knownPID`，避免后续 `pid` getter 走 pgrep fallback
    func stop() async {
        // 情况 A: 知道 PID（正常情况，本 app 启动的 AstrBot）
        if let pid = knownPID {
            kill(pid, SIGTERM)

            // 轮询等进程退出，最多 5 秒
            var status: Int32 = 0
            var elapsed: TimeInterval = 0
            while elapsed < 5 {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid { break }  // 已退出
                try? await Task.sleep(nanoseconds: 100_000_000)
                elapsed += 0.1
            }

            // 兜底：还没退出就 SIGKILL，再等 1s
            if kill(pid, 0) == 0 {
                AppLog.warn("AstrBot pid=\(pid) 未响应 SIGTERM，发送 SIGKILL")
                kill(pid, SIGKILL)
                elapsed = 0
                while elapsed < 1 && kill(pid, 0) == 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    elapsed += 0.1
                }
            }

            // 进程确认已退出，再清状态
            knownPID = nil
            startedByUs = false
            AppLog.info("AstrBot stopped: pid=\(pid)")
            return
        }

        // 情况 B: 不知道 PID（孤儿 / 外部启动的 AstrBot）
        _ = ShellExecutor.runSync("/usr/bin/pkill", arguments: ["-f", "astrbot run"])
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 等 1s 让 pkill 生效
        startedByUs = false
        AppLog.info("AstrBot stopped via pkill (no known PID)")
    }

    /// 查询 AstrBot 是否在运行
    /// 策略：
    /// 1. 优先用已知 PID（knownPID）通过 `kill(pid, 0)` 检测（最可靠）
    /// 2. Fallback：用具体路径 pgrep 查找（避免误匹配 "pkill -f 'astrbot run'" 等 shell 命令）
    func isRunning() -> Bool {
        // 1. 优先用 knownPID 检测
        if let pid = knownPID {
            // kill(pid, 0) 成功（返回 0）表示进程存在
            if kill(pid, 0) == 0 { return true }
            // knownPID 已失效，清除
            knownPID = nil
            startedByUs = false
            return false
        }

        // 2. Fallback：用具体脚本路径查找（uv tool 安装路径）
        //    避免字面匹配 `pkill -f "astrbot run"` 之类的 shell 命令
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/astrbot run",        // uv tool 安装
            "\(home)/.local/share/uv/tools/astrbot/bin/astrbot run",
            "/usr/local/bin/astrbot run",             // Homebrew Intel
            "/opt/homebrew/bin/astrbot run"          // Homebrew AS
        ]
        for pattern in candidates {
            let result = ShellExecutor.runSync("/usr/bin/pgrep", arguments: ["-f", pattern])
            if result.success, !result.stdout.isEmpty {
                return true
            }
        }
        return false
    }

    /// 获取 AstrBot 当前 PID
    func currentPID() -> pid_t? {
        // 优先用 knownPID
        if let pid = knownPID, kill(pid, 0) == 0 {
            return pid
        }
        // Fallback: 用具体路径查找
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/astrbot run",
            "\(home)/.local/share/uv/tools/astrbot/bin/astrbot run",
            "/usr/local/bin/astrbot run",
            "/opt/homebrew/bin/astrbot run"
        ]
        for pattern in candidates {
            let result = ShellExecutor.runSync("/usr/bin/pgrep", arguments: ["-fn", pattern])
            if result.success, let firstLine = result.stdout.split(separator: "\n").first {
                let pidStr = firstLine.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? ""
                if let pid = pid_t(pidStr), pid > 0 { return pid }
            }
        }
        return nil
    }

    /// 获取所有 AstrBot 实例
    func allInstances() -> [(pid: pid_t, elapsed: String)] {
        let result = ShellExecutor.runSync("/usr/bin/pgrep", arguments: ["-fl", "astrbot run"])
        guard result.success else { return [] }
        return result.stdout.split(separator: "\n").compactMap { line -> (pid_t, String)? in
            // 排除 pgrep 自身
            if line.contains("pgrep") { return nil }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = pid_t(parts[0]) else { return nil }
            let elapsed = parts.dropFirst().dropLast().joined(separator: " ")
            return (pid, elapsed)
        }
    }

    /// 清理孤儿实例（保留最老的）
    func cleanupOrphans() throws {
        let instances = allInstances()
        guard instances.count > 1 else { return }

        // 保留 PID 最小的（最早启动的）
        let keep = instances.min(by: { $0.pid < $1.pid })!
        for inst in instances where inst.pid != keep.pid {
            kill(inst.pid, SIGTERM)
        }
        AppLog.info("Cleaned up \(instances.count - 1) orphan AstrBot instances, kept PID \(keep.pid)")
    }

    /// 构建启动命令（参考 AstrBotController.buildLaunchCommand）
    private func buildLaunchCommand(mode: AstrBotLaunchMode, settings: AppSettings) throws -> (String, [String]) {
        switch mode {
        case .uvToolRun:
            guard let astrbotPath = AstrBotController.detectAstrbotPath() else {
                throw NSError(
                    domain: "AstrBotProcessManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "未找到 astrbot 命令"]
                )
            }
            return (astrbotPath, ["run"])
        case .customCommand:
            let command = settings.astrBotCustomCommand.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else {
                throw NSError(
                    domain: "AstrBotProcessManager",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "请先在设置中输入自定义命令"]
                )
            }
            return ShellParser.parse(command)
        case .executablePath:
            let path = settings.astrBotExecutablePath.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else {
                throw NSError(
                    domain: "AstrBotProcessManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "请先在设置中指定 AstrBot 可执行文件路径"]
                )
            }
            let expandedPath = (path as NSString).expandingTildeInPath
            guard ShellExecutor.exists(expandedPath) else {
                throw NSError(
                    domain: "AstrBotProcessManager",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "文件不存在: \(expandedPath)"]
                )
            }
            return (expandedPath, [])
        case .shellScript:
            let path = settings.astrBotScriptPath.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else {
                throw NSError(
                    domain: "AstrBotProcessManager",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "请先在设置中指定启动脚本路径"]
                )
            }
            let expandedPath = (path as NSString).expandingTildeInPath
            guard ShellExecutor.exists(expandedPath) else {
                throw NSError(
                    domain: "AstrBotProcessManager",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "脚本不存在: \(expandedPath)"]
                )
            }
            guard let bash = ShellExecutor.which("bash") else {
                throw NSError(
                    domain: "AstrBotProcessManager",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "未找到 bash"]
                )
            }
            return (bash, [expandedPath])
        }
    }
}
