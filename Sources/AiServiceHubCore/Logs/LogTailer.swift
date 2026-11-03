import Foundation

/// tailer 的运行状态
public enum TailerState: Sendable, Equatable {
    case idle
    /// 文件还不存在，正在等待
    case waitingForFile
    /// 正在跟随
    case following
    case stopped
}

/// 日志跟随器
///
/// 负责把一个日志来源（文件 / 文件通配 / 子进程输出）转成行流。
///
/// 与旧实现的关键差异：
/// - **生命周期独立于界面**：tailer 常驻，切换服务不会中断其他来源的采集。
/// - **文件不存在时等待并重试**，而不是提示一次就放弃。
/// - **文件被截断或轮转时自动重新跟随**。
public final class LogTailer: @unchecked Sendable {
    public typealias LineHandler = @Sendable ([String]) -> Void
    public typealias StateHandler = @Sendable (TailerState) -> Void

    private let spec: LogSourceSpec
    private let onLines: LineHandler
    private let onStateChange: StateHandler
    private let historyByteLimit: Int
    private let pollInterval: TimeInterval

    private let queue: DispatchQueue
    private let parser = LineParser()

    private var timer: DispatchSourceTimer?
    private var process: Process?
    private var processPipe: Pipe?

    private var resolvedPath: String?
    private var fileIdentity: String?
    private var offset: UInt64 = 0
    private var hasEmittedHistory = false

    public init(
        spec: LogSourceSpec,
        historyByteLimit: Int = 64 * 1024,
        pollInterval: TimeInterval = 1,
        onLines: @escaping LineHandler,
        onStateChange: @escaping StateHandler
    ) {
        self.spec = spec
        self.historyByteLimit = historyByteLimit
        self.pollInterval = pollInterval
        self.onLines = onLines
        self.onStateChange = onStateChange
        self.queue = DispatchQueue(label: "logtailer.\(spec.id)", qos: .utility)
    }

    public func start() {
        switch spec.kind {
        case .file, .filePattern:
            startFileTailing()
        case .command:
            startCommandStreaming()
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        processPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        processPipe = nil
        onStateChange(.stopped)
    }

    // MARK: - 文件

    private func startFileTailing() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.pollFile()
        }
        timer.resume()
        self.timer = timer
    }

    private func pollFile() {
        guard let url = resolveURL() else {
            if resolvedPath != nil {
                resolvedPath = nil
                fileIdentity = nil
                offset = 0
                hasEmittedHistory = false
            }
            onStateChange(.waitingForFile)
            return
        }

        let path = url.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            onStateChange(.waitingForFile)
            return
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let identity = Self.identityString(for: attributes)

        // 文件被替换或截断 —— 重新从头跟随
        if let previous = fileIdentity, previous != identity {
            offset = 0
            hasEmittedHistory = false
            parser.flushRemaining()
        }
        fileIdentity = identity
        resolvedPath = path

        // 首次跟随：先吐出历史
        if !hasEmittedHistory {
            hasEmittedHistory = true
            let historyStart = size > UInt64(historyByteLimit) ? size - UInt64(historyByteLimit) : 0
            if size > historyStart, let history = readRange(url: url, from: historyStart, to: size) {
                let text = String(data: history, encoding: .utf8) ?? ""
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                // 丢掉可能不完整的首行
                if historyStart > 0, let first = lines.first, !text.hasPrefix("\n") {
                    let trimmed = lines.dropFirst()
                    if !trimmed.isEmpty { onLines(Array(trimmed)) }
                } else if !lines.isEmpty {
                    onLines(lines)
                }
            }
            offset = size
            onStateChange(.following)
            return
        }

        // 读取新增内容
        if size > offset, let data = readRange(url: url, from: offset, to: size) {
            offset = size
            let lines = parser.feed(data)
            if !lines.isEmpty { onLines(lines) }
        } else if size < offset {
            // 被截断
            offset = 0
            hasEmittedHistory = false
        }
        onStateChange(.following)
    }

    private func readRange(url: URL, from: UInt64, to: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: from)
            return handle.readData(ofLength: Int(to - from))
        } catch {
            return nil
        }
    }

    /// 文件身份：inode + 创建时间，用于识别轮转
    static func identityString(for attributes: [FileAttributeKey: Any]) -> String {
        let number = (attributes[.systemFileNumber] as? NSNumber)?.stringValue ?? ""
        let created = (attributes[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(number)-\(created)"
    }

    /// 解析实际要跟随的文件（支持通配）
    private func resolveURL() -> URL? {
        switch spec.kind {
        case .file(let path):
            let expanded = PathExpander.expand(path)
            return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil

        case .filePattern(let pattern):
            let expanded = PathExpander.expand(pattern)
            let directory = (expanded as NSString).deletingLastPathComponent
            let fileName = (expanded as NSString).lastPathComponent
            guard fileName.contains("*"),
                  let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                return nil
            }
            // 取最新的一个
            let matches = entries.filter { Self.matches(name: $0, pattern: fileName) }
            let newest = matches.max { lhs, rhs in
                let left = Self.modificationDate(at: directory, name: lhs)
                let right = Self.modificationDate(at: directory, name: rhs)
                return (left ?? .distantPast) < (right ?? .distantPast)
            }
            guard let newest else { return nil }
            return URL(fileURLWithPath: directory).appendingPathComponent(newest)

        case .command:
            return nil
        }
    }

    static func matches(name: String, pattern: String) -> Bool {
        let regex = "^" + pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*") + "$"
        guard let expression = try? NSRegularExpression(pattern: regex) else { return false }
        let range = NSRange(name.startIndex..., in: name)
        return expression.firstMatch(in: name, range: range) != nil
    }

    private static func modificationDate(at directory: String, name: String) -> Date? {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    // MARK: - 子进程

    private func startCommandStreaming() {
        guard case .command(let executable, let arguments) = spec.kind else { return }

        let resolved = ExecutableLocator.shared.which(executable) ?? executable
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            let lines = self.parser.feed(data)
            if !lines.isEmpty {
                self.onLines(lines)
            }
        }

        do {
            try process.run()
        } catch {
            AppLog.error("无法启动日志来源 \(resolved)：\(error.localizedDescription)")
            onStateChange(.stopped)
            return
        }

        self.process = process
        self.processPipe = pipe
        onStateChange(.following)
    }
}
