import Foundation
import Darwin

/// 一个匹配的进程快照
public struct ProcessSnapshot: Sendable, Equatable {
    public let pid: pid_t
    public let command: String
    public let elapsed: String
    public let startTimeToken: String?

    public init(pid: pid_t, command: String, elapsed: String, startTimeToken: String?) {
        self.pid = pid
        self.command = command
        self.elapsed = elapsed
        self.startTimeToken = startTimeToken
    }
}

/// 进程与端口探测
///
/// 需要调用外部命令的部分都是异步的，避免在主线程上同步等待 `pgrep` / `lsof`。
public struct ProcessInspector: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    // MARK: - 进程存活

    /// 进程是否存活
    public static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// 进程的启动时间标识
    ///
    /// 用来区分「同一个 pid」与「同一个进程」：pid 会被系统回收复用，
    /// 只有 pid + 启动时间都一致，才能认定还是当初那个进程。
    /// 这里走 `sysctl(KERN_PROC_PID)` 拿 `p_starttime`，不依赖 `ps` 的本地化输出。
    public static func startTimeToken(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        guard started.tv_sec > 0 else { return nil }
        return "\(started.tv_sec).\(started.tv_usec)"
    }

    /// 判断「仍是当初那个进程」
    public static func matchesIdentity(pid: pid_t, startTimeToken: String?) -> Bool {
        guard isAlive(pid: pid) else { return false }
        guard let startTimeToken else { return true }  // 没有基准信息时只判存活
        guard let current = Self.startTimeToken(pid: pid) else { return false }
        return current == startTimeToken
    }

    // MARK: - 进程匹配

    /// 找出第一个匹配任一模式的进程
    public func firstPID(matching patterns: [String]) async -> pid_t? {
        await allProcesses(matching: patterns).first?.pid
    }

    /// 找出所有匹配任一模式的进程
    public func allProcesses(matching patterns: [String]) async -> [ProcessSnapshot] {
        guard !patterns.isEmpty else { return [] }
        var seen = Set<pid_t>()
        var result: [ProcessSnapshot] = []

        for pattern in patterns {
            let output = await runner.runIgnoringFailure(
                "/usr/bin/pgrep",
                arguments: ["-fl", pattern],
                timeout: .seconds(10)
            )
            for line in output.stdout.split(separator: "\n") {
                guard let snapshot = Self.parsePgrepLine(String(line)) else { continue }
                if seen.insert(snapshot.pid).inserted {
                    result.append(snapshot)
                }
            }
        }
        return result
    }

    /// 解析 `pgrep -fl` 的一行：`PID ELAPSED COMMAND...`
    static func parsePgrepLine(_ line: String) -> ProcessSnapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("pgrep") else { return nil }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, let pid = pid_t(parts[0]), pid > 0 else { return nil }
        // pgrep -fl 的格式是：PID ELAPSED COMMAND
        let elapsed = parts.count >= 3 ? String(parts[1]) : ""
        let command = parts.count >= 3
            ? parts.dropFirst(2).joined(separator: " ")
            : String(parts[1])
        return ProcessSnapshot(
            pid: pid,
            command: command,
            elapsed: elapsed,
            startTimeToken: startTimeToken(pid: pid)
        )
    }

    // MARK: - 端口

    /// 某个进程正在监听的 TCP 端口
    public func listeningPorts(pid: pid_t) async -> [Int] {
        let output = await runner.runIgnoringFailure(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "\(pid)"],
            timeout: .seconds(10)
        )
        return Self.parseListeningPorts(output.stdout)
    }

    /// 某个端口是否处于 LISTEN
    public func isPortListening(_ port: Int) async -> Bool {
        let output = await runner.runIgnoringFailure(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"],
            timeout: .seconds(10)
        )
        return !Self.parseListeningPorts(output.stdout).isEmpty
    }

    /// 解析 `lsof -nP -iTCP -sTCP:LISTEN` 的输出，取出监听端口
    static func parseListeningPorts(_ output: String) -> [Int] {
        var ports = Set<Int>()
        for line in output.split(separator: "\n") {
            // 形如：node 47228 djx 14u IPv4 ... TCP 127.0.0.1:3080 (LISTEN)
            guard let range = line.range(of: #"TCP\s+\S+:(\d+)\s+\(LISTEN\)"#, options: .regularExpression) else {
                continue
            }
            let portText = line[range].split(separator: ":").last.map(String.init) ?? ""
            if let port = Int(portText) { ports.insert(port) }
        }
        return ports.sorted()
    }
}
