import Foundation

/// 「持有子进程」模式的驱动
public struct ProcessDriver: Sendable {
    private let inspector: ProcessInspector

    public init(inspector: ProcessInspector = ProcessInspector()) {
        self.inspector = inspector
    }

    /// 启动进程
    ///
    /// - Returns: 进程记录（写入所有权账本）
    @discardableResult
    public func start(spec: ProcessSpec, serviceID: UUID) throws -> OwnedProcessRecord {
        let executable = PathExpander.expand(spec.executable)
        let workingDirectory = spec.workingDirectory.map { PathExpander.expand($0) }

        let resolved: (executable: String, arguments: [String])
        if spec.shellMode {
            // 经 shell：整条命令交给 /bin/sh -c
            let command = ([executable] + spec.arguments).map(ShellQuoting.quote).joined(separator: " ")
            resolved = ("/bin/sh", ["-c", command])
        } else {
            resolved = (executable, spec.arguments)
        }

        guard let pid = DaemonSpawner.spawn(
            executable: resolved.executable,
            arguments: resolved.arguments,
            environment: spec.environment.isEmpty ? nil : spec.environment,
            workingDirectory: workingDirectory,
            detached: spec.ownership.detached
        ) else {
            throw ProcessDriverError.spawnFailed(executable)
        }

        return OwnedProcessRecord(
            serviceID: serviceID,
            pid: pid,
            startTimeToken: ProcessInspector.startTimeToken(pid: pid),
            executable: resolved.executable,
            arguments: resolved.arguments,
            detached: spec.ownership.detached
        )
    }

    /// 停止进程
    ///
    /// SIGTERM → 等待 5 秒 → SIGKILL 兜底。
    /// 只终止「确实是本程序启动的那个」进程（pid + 启动时间双重校验）。
    public func stop(record: OwnedProcessRecord) async {
        guard ProcessInspector.isAlive(pid: record.pid) else { return }
        if !ProcessInspector.matchesIdentity(pid: record.pid, startTimeToken: record.startTimeToken) {
            AppLog.warn("PID \(record.pid) 已被系统复用，跳过终止")
            return
        }

        kill(record.pid, SIGTERM)

        var elapsed: TimeInterval = 0
        while elapsed < 5 {
            if !ProcessInspector.isAlive(pid: record.pid) {
                ProcessInspector.reap(pid: record.pid)
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            elapsed += 0.1
        }

        if ProcessInspector.isAlive(pid: record.pid) {
            AppLog.warn("进程 \(record.pid) 未响应 SIGTERM，发送 SIGKILL")
            kill(record.pid, SIGKILL)
            elapsed = 0
            while elapsed < 1 && ProcessInspector.isAlive(pid: record.pid) {
                try? await Task.sleep(nanoseconds: 100_000_000)
                elapsed += 0.1
            }
        }
        ProcessInspector.reap(pid: record.pid)
    }

    /// 探测进程状态
    public func status(spec: ProcessSpec, record: OwnedProcessRecord?) async -> ProcessStatus {
        // 1. 本程序持有的进程：直接用 pid + 启动时间校验
        if let record {
            if ProcessInspector.matchesIdentity(pid: record.pid, startTimeToken: record.startTimeToken) {
                return ProcessStatus(
                    pid: record.pid,
                    startTimeToken: record.startTimeToken,
                    isRunning: true,
                    startedByUs: true
                )
            }
        }

        // 2. 外部启动的进程：按命令行匹配
        let patterns = spec.processMatch.isEmpty ? [spec.executable] : spec.processMatch
        let processes = await inspector.allProcesses(matching: patterns)
        guard let first = processes.first else {
            return ProcessStatus(pid: nil, startTimeToken: nil, isRunning: false, startedByUs: false)
        }
        return ProcessStatus(
            pid: first.pid,
            startTimeToken: first.startTimeToken,
            isRunning: true,
            startedByUs: false
        )
    }
}

/// 进程探测结果
public struct ProcessStatus: Sendable, Equatable {
    public let pid: Int32?
    public let startTimeToken: String?
    public let isRunning: Bool
    /// 是否由本程序启动
    public let startedByUs: Bool

    public init(pid: Int32?, startTimeToken: String?, isRunning: Bool, startedByUs: Bool) {
        self.pid = pid
        self.startTimeToken = startTimeToken
        self.isRunning = isRunning
        self.startedByUs = startedByUs
    }
}

/// 进程驱动错误
public enum ProcessDriverError: Error, LocalizedError {
    case spawnFailed(String)

    public var errorDescription: String? {
        switch self {
        case .spawnFailed(let executable):
            return "无法启动进程：\(executable)"
        }
    }
}

/// shell 参数转义
public enum ShellQuoting {
    /// 把参数安全地拼进一条 shell 命令
    public static func quote(_ argument: String) -> String {
        if argument.isEmpty { return "''" }
        let safe = argument.allSatisfy { character in
            character.isLetter || character.isNumber || "-_./=:@".contains(character)
        }
        if safe { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
