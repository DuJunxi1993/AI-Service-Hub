import Foundation
import Darwin

/// 一个匹配的进程快照
public struct ProcessSnapshot: Sendable, Equatable {
    public let pid: pid_t
    public let command: String
    public let startTimeToken: String?

    public init(pid: pid_t, command: String, startTimeToken: String?) {
        self.pid = pid
        self.command = command
        self.startTimeToken = startTimeToken
    }
}

/// 一次进程表枚举的结果
///
/// 本轮重构的一个关键教训：macOS 27 上的 `pgrep -f` 会漏掉某些进程
/// （实测漏掉了由 GUI app 派生的 `dsh web`），而 `ps -A` 能看到全部。
/// 因此进程匹配统一走 `ps`，并且**每轮只枚举一次**，在内存里匹配所有服务。
public struct ProcessTable: Sendable {
    public struct Entry: Sendable, Equatable {
        public let pid: pid_t
        public let command: String

        public init(pid: pid_t, command: String) {
            self.pid = pid
            self.command = command
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// 找出命令行包含任一模式的进程
    public func matching(_ patterns: [String]) -> [ProcessSnapshot] {
        guard !patterns.isEmpty else { return [] }
        var result: [ProcessSnapshot] = []
        for entry in entries {
            guard patterns.contains(where: { entry.command.contains($0) }) else { continue }
            result.append(ProcessSnapshot(
                pid: entry.pid,
                command: entry.command,
                startTimeToken: ProcessInspector.startTimeToken(pid: entry.pid)
            ))
        }
        return result
    }

    /// 解析 `ps -A -o pid=,command=` 的输出
    static func parse(_ output: String) -> ProcessTable {
        var entries: [Entry] = []
        entries.reserveCapacity(1024)
        for line in output.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(where: { $0 == " " }),
                  let pid = pid_t(trimmed[..<space]) else { continue }
            let command = String(trimmed[trimmed.index(after: space)...])
            guard !command.isEmpty else { continue }
            entries.append(Entry(pid: pid, command: command))
        }
        return ProcessTable(entries: entries)
    }
}

/// 进程与端口探测
///
/// 需要调用外部命令的部分都是异步的，避免在主线程上同步等待。
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

    // MARK: - 进程枚举

    /// 枚举当前全部进程
    public func snapshot() async -> ProcessTable {
        let output = await runner.runIgnoringFailure(
            "/bin/ps",
            arguments: ["-A", "-o", "pid=,command="],
            timeout: .seconds(10)
        )
        return ProcessTable.parse(output.stdout)
    }

    /// 找出匹配任一模式的进程（一次性枚举）
    public func allProcesses(matching patterns: [String]) async -> [ProcessSnapshot] {
        await snapshot().matching(patterns)
    }

    /// 找出第一个匹配的进程
    public func firstPID(matching patterns: [String]) async -> pid_t? {
        await allProcesses(matching: patterns).first?.pid
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
        // 形如：node 47228 djx 14u IPv4 ... TCP 127.0.0.1:3080 (LISTEN)
        let pattern = #"TCP\s+\S+:(\d+)\s+\(LISTEN\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var ports = Set<Int>()
        for line in output.split(separator: "\n") {
            let text = String(line)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let portRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            if let port = Int(text[portRange]) {
                ports.insert(port)
            }
        }
        return ports.sorted()
    }
}
