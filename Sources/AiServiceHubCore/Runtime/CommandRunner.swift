import Foundation

/// 一次命令执行的结果
public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var success: Bool { exitCode == 0 }
}

/// 命令执行错误
public enum CommandError: Error, LocalizedError, Equatable {
    case launchFailed(String)
    case timedOut(seconds: Double)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return "命令启动失败：\(message)"
        case .timedOut(let seconds): return "命令超时（\(String(format: "%.1f", seconds))s）"
        case .cancelled: return "命令已取消"
        }
    }
}

/// 异步命令执行器
///
/// 与旧实现的关键差异：
/// - **stdout / stderr 并发读取**：旧实现先读完 stdout 再读 stderr，
///   子进程若先把 stderr 写满管道就会死锁。
/// - **支持超时与取消**。
public struct CommandRunner: Sendable {
    public init() {}

    /// 执行命令并等待结束
    ///
    /// - Parameters:
    ///   - executable: 可执行文件的绝对路径
    ///   - arguments: 参数列表
    ///   - environment: 额外环境变量（与当前进程环境合并）
    ///   - workingDirectory: 工作目录
    ///   - timeout: 超时时长，超时后终止进程并抛出 `CommandError.timedOut`
    public func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> CommandResult {
        let box = CommandBox(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        // box 的生命周期必须覆盖整个 await：回调里用强引用建立临时循环，
        // 完成时由 box.teardown() 拆掉。这里再兜一层，确保 await 期间不被释放。
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            box.cancel()
        }
        withExtendedLifetime(box) {}
        return result
    }

    /// 执行命令，忽略退出码（失败时返回空输出）
    public func runIgnoringFailure(
        _ executable: String,
        arguments: [String] = [],
        timeout: Duration = .seconds(30)
    ) async -> CommandResult {
        (try? await run(executable, arguments: arguments, timeout: timeout))
            ?? CommandResult(exitCode: -1, stdout: "", stderr: "执行失败")
    }
}

/// 单次执行的内部状态容器
///
/// Foundation 的 Process / Pipe / FileHandle 不满足 Sendable，这里以
/// `@unchecked Sendable` 封装，并用一把锁保护所有共享状态。
///
/// 完成信号以 **进程退出** 为准：进程结束后关闭父进程侧的写入端、把管道里
/// 剩余数据读干净，然后恢复 continuation。不依赖 EOF 事件是否送达。
private final class CommandBox: @unchecked Sendable {
    private enum Stream {
        case stdout
        case stderr
    }

    private let executable: String
    private let arguments: [String]
    private let environment: [String: String]?
    private let workingDirectory: String?

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var didResume = false
    private var continuation: CheckedContinuation<CommandResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var timeoutSeconds: Double = 30

    init(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: String?
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    // MARK: - 启动

    func start(timeout: Duration, continuation: CheckedContinuation<CommandResult, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()

        timeoutSeconds = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18

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

        // 强引用捕获：保证 box 在 process / pipe 存活期间一直活着
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self.append(data, to: .stdout)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self.append(data, to: .stderr)
        }

        process.terminationHandler = { [self] _ in
            self.drainAndFinish()
        }

        do {
            try process.run()
        } catch {
            resume(throwing: CommandError.launchFailed(error.localizedDescription))
            return
        }

        timeoutTask = Task { [self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.handleTimeout()
        }
    }

    func cancel() {
        if process.isRunning {
            process.terminate()
        }
    }

    // MARK: - 数据累积

    private func append(_ data: Data, to stream: Stream) {
        lock.lock()
        switch stream {
        case .stdout: stdoutData.append(data)
        case .stderr: stderrData.append(data)
        }
        lock.unlock()
    }

    // MARK: - 完成

    /// 进程已退出：关闭父进程侧写端 → 读净管道 → 完成
    private func drainAndFinish() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // 关闭父进程持有的写端，确保读端一定看到 EOF
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        if let remaining = try? stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
           !remaining.isEmpty {
            append(remaining, to: .stdout)
        }
        if let remaining = try? stderrPipe.fileHandleForReading.readDataToEndOfFile(),
           !remaining.isEmpty {
            append(remaining, to: .stderr)
        }

        finish()
    }

    private func handleTimeout() {
        lock.lock()
        let alreadyResumed = didResume
        lock.unlock()
        guard !alreadyResumed else { return }

        if process.isRunning {
            process.terminate()
        }
        resume(throwing: CommandError.timedOut(seconds: timeoutSeconds))
    }

    private func finish() {
        let exitCode = process.terminationStatus

        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let out = stdoutData
        let err = stderrData
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        teardown()

        let result = CommandResult(
            exitCode: exitCode,
            stdout: String(data: out, encoding: .utf8) ?? "",
            stderr: String(data: err, encoding: .utf8) ?? ""
        )
        continuation?.resume(returning: result)
    }

    private func resume(throwing error: Error) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        teardown()
        continuation?.resume(throwing: error)
    }

    /// 拆掉所有强引用，避免 box 常驻内存
    private func teardown() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil

        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
