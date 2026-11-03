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
/// - **stdout / stderr 并发读取**：旧实现先 `readDataToEndOfFile()` 读 stdout 再读 stderr，
///   子进程若先把 stderr 写满管道就会死锁。
/// - **支持超时与取消**。
/// - **全程在主线程之外**：调用方负责不要在主 actor 上 await 长时间命令。
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
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.start(timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            box.cancel()
        }
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
/// Foundation 的 Process / Pipe 不满足 Sendable，这里以 `@unchecked Sendable`
/// 封装，并用一把锁保护所有共享状态。
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
    private var stdoutFinished = false
    private var stderrFinished = false
    private var processExited = false
    private var didResume = false
    private var didTimeout = false
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

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.markStreamFinished(.stdout)
            } else {
                self?.append(data, to: .stdout)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.markStreamFinished(.stderr)
            } else {
                self?.append(data, to: .stderr)
            }
        }

        process.terminationHandler = { [weak self] _ in
            self?.markProcessExited()
        }

        do {
            try process.run()
        } catch {
            resume(throwing: CommandError.launchFailed(error.localizedDescription))
            return
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.handleTimeout()
        }
    }

    func cancel() {
        guard process.isRunning else { return }
        process.terminate()
    }

    // MARK: - 状态更新

    private func append(_ data: Data, to stream: Stream) {
        lock.lock()
        switch stream {
        case .stdout: stdoutData.append(data)
        case .stderr: stderrData.append(data)
        }
        lock.unlock()
    }

    private func markStreamFinished(_ stream: Stream) {
        lock.lock()
        switch stream {
        case .stdout: stdoutFinished = true
        case .stderr: stderrFinished = true
        }
        let ready = stdoutFinished && stderrFinished && processExited
        lock.unlock()
        if ready { finish() }
    }

    private func markProcessExited() {
        lock.lock()
        processExited = true
        let ready = stdoutFinished && stderrFinished
        lock.unlock()
        if ready { finish() }
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
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        let out = stdoutData
        let err = stderrData
        lock.unlock()

        timeoutTask?.cancel()
        timeoutTask = nil

        let result = CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: out, encoding: .utf8) ?? "",
            stderr: String(data: err, encoding: .utf8) ?? ""
        )
        resume(returning: result)
    }

    private func resume(returning result: CommandResult) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        lock.unlock()

        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: result)
    }

    private func resume(throwing error: Error) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        lock.unlock()

        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(throwing: error)
    }
}
