import Foundation

/// 日志数据源
enum LogSource: String, CaseIterable, Identifiable, Hashable {
    case astrbot
    case napcat
    case shipyard

    var id: String { rawValue }

    /// 转为 ServiceType
    var serviceType: ServiceType {
        switch self {
        case .astrbot: return .astrbot
        case .napcat: return .napcat
        case .shipyard: return .shipyard
        }
    }

    var displayName: String {
        switch self {
        case .astrbot: return "AstrBot"
        case .napcat: return "NapCat"
        case .shipyard: return "Shipyard"
        }
    }
}

/// 日志行
struct LogLine: Identifiable, Hashable {
    let id: UUID = UUID()
    let timestamp: Date
    let level: LogLevel
    let source: LogSource
    let content: String
}

enum LogLevel: String, CaseIterable, Identifiable, Hashable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    var id: String { rawValue }

    static func detect(from line: String) -> LogLevel {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("err ") || lower.contains("fail") {
            return .error
        }
        if lower.contains("warn") {
            return .warn
        }
        if lower.contains("debug") {
            return .debug
        }
        return .info
    }
}

// MARK: - 行解析器（行缓冲）

/// 把字节流按 \n 切分为完整行，保留未完成的半行
final class LineParser: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    /// 喂入字节，返回完整行列表（剩余半行留在 buffer）
    func feed(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        return drainCompleteLinesLocked()
    }

    /// 强制 flush 剩余 buffer（如 EOF）
    func flushRemaining() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let line = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll(keepingCapacity: true)
        return line.isEmpty ? nil : line
    }

    private func drainCompleteLinesLocked() -> [String] {
        var lines: [String] = []
        var lastNewlineIndex: Int? = nil
        for i in 0..<buffer.count {
            if buffer[i] == 0x0A {
                lastNewlineIndex = i
            }
        }
        guard let lastIdx = lastNewlineIndex else { return [] }
        let completeData = buffer.prefix(lastIdx + 1)
        buffer = Data(buffer.suffix(from: lastIdx + 1))
        var start = 0
        for i in 0..<completeData.count {
            if completeData[i] == 0x0A {
                let lineData = completeData.subdata(in: start..<i)
                if let str = String(data: lineData, encoding: .utf8) {
                    lines.append(str)
                }
                start = i + 1
            }
        }
        return lines
    }
}

// MARK: - 非 actor 包装类

/// 文件监听桥接器（非 @MainActor）
final class FileWatcherBridge: @unchecked Sendable {
    private let handle: FileHandle
    private let fd: Int32
    private let onLines: @Sendable ([String], Bool) -> Void
    private var source: DispatchSourceFileSystemObject?

    init(handle: FileHandle, onLines: @escaping @Sendable ([String], Bool) -> Void) {
        self.handle = handle
        self.fd = handle.fileDescriptor
        self.onLines = onLines
    }

    func start() {
        let h = handle
        let cb = onLines
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.extend, .write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler {
            let data = h.availableData
            if data.isEmpty {
                cb([], true)
            } else {
                cb([String(data: data, encoding: .utf8) ?? ""], false)
            }
        }
        source.setCancelHandler {
            try? h.close()
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}

/// Docker 日志读取器（非 @MainActor）
final class DockerLogReader: @unchecked Sendable {
    private let process: Process
    private let handle: FileHandle
    private let onLines: @Sendable ([String]) -> Void
    private let onEOF: @Sendable () -> Void

    init(
        process: Process,
        onLines: @escaping @Sendable ([String]) -> Void,
        onEOF: @escaping @Sendable () -> Void
    ) {
        self.process = process
        self.handle = (process.standardOutput as! Pipe).fileHandleForReading
        self.onLines = onLines
        self.onEOF = onEOF
    }

    func start() {
        let h = handle
        let lineCb = onLines
        let eofCb = onEOF
        h.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                // EOF：清理 handler 避免重复触发
                fh.readabilityHandler = nil
                eofCb()
            } else if let str = String(data: data, encoding: .utf8) {
                lineCb([str])
            }
        }
    }

    func stop() {
        handle.readabilityHandler = nil
        process.terminate()
    }

    deinit {
        handle.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }
}

// MARK: - 日志观察器

/// 日志观察器（监听 AstrBot 日志文件 / docker logs 流）
///
/// 架构：
/// 1. 后台线程（readabilityHandler / setEventHandler）解析日志行
/// 2. 行直接累积到 BackgroundLogAccumulator（线程安全）
/// 3. Timer 每 1 秒 flush 一次到 @MainActor，更新 @Published lines
///
/// 这种设计避免了：
/// - 每次 callback 都创建 @MainActor Task（高开销）
/// - 频繁触发 SwiftUI 重新渲染
@MainActor
final class LogWatcher: ObservableObject {
    @Published var lines: [LogLine] = []
    @Published private(set) var isStreaming: Bool = false
    @Published var autoScroll: Bool = true
    @Published var isPaused: Bool = false  // 暂停标志：暂停时丢弃新行（保留历史）

    private let maxLines = 1000
    private var fileWatcher: FileWatcherBridge?
    private var watchedFile: String?
    private var dockerReader: DockerLogReader?
    private var dockerProcess: Process?
    private var accumulator: BackgroundLogAccumulator?

    /// 清空指定 source 的日志
    func clear(source: LogSource) {
        lines.removeAll { $0.source == source }
    }

    /// 清空所有日志
    func clear() {
        lines.removeAll()
    }

    /// 停止所有监听
    func stop() {
        accumulator?.stop()
        accumulator = nil

        fileWatcher?.stop()
        fileWatcher = nil
        watchedFile = nil

        dockerReader?.stop()
        dockerReader = nil
        dockerProcess = nil

        isStreaming = false
    }

    /// 监听 AstrBot 日志文件
    func watchAstrBotLogFile(_ path: String) {
        stop()
        setupAccumulator()

        let expanded = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expanded) else {
            append(.init(timestamp: Date(), level: .warn, source: .astrbot, content: "日志文件不存在: \(expanded)"))
            return
        }

        // 读取已有内容（最后 500 行）- 同步直接 append
        readLastLines(expanded, count: 500)

        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: expanded)) else {
            append(.init(timestamp: Date(), level: .error, source: .astrbot, content: "无法打开日志文件"))
            return
        }
        _ = try? handle.seekToEnd()

        // 用非 actor 包装类 + 行缓冲
        let parser = LineParser()
        let acc = accumulator!
        let watcher = FileWatcherBridge(handle: handle) { [weak self] rawStrings, truncated in
            // 后台线程：行切分
            var allLines: [String] = []
            for raw in rawStrings {
                if raw.isEmpty { continue }
                let parsed = parser.feed(Data(raw.utf8))
                allLines.append(contentsOf: parsed)
            }
            if truncated {
                let remaining = parser.flushRemaining()
                if let remaining { allLines.append(remaining) }
                let fd = handle.fileDescriptor
                let expandedCopy = expanded
                Task { @MainActor [weak self] in
                    self?.handleLogFileEvent(fd: fd, expanded: expandedCopy)
                }
            }
            // 直接累积到 background buffer（无 Task 调度）
            if !allLines.isEmpty {
                // 检测 WebUI URL（AstrBot）
                for line in allLines {
                    if let url = WebUIURLDetector.extract(from: line, for: .astrbot) {
                        NotificationCenter.default.post(
                            name: .webUIDetected,
                            object: nil,
                            userInfo: ["source": LogSource.astrbot, "url": url]
                        )
                    }
                }
                let now = Date()
                let entries: [LogLine] = allLines.map { line in
                    LogLine(
                        timestamp: now,
                        level: LogLevel.detect(from: line),
                        source: .astrbot,
                        content: line
                    )
                }
                acc.appendBatch(entries)
            }
        }
        watcher.start()
        self.fileWatcher = watcher
        self.watchedFile = expanded
        self.isStreaming = true

        append(.init(timestamp: Date(), level: .debug, source: .astrbot, content: "已连接到日志文件: \(expanded)"))
    }

    /// 处理日志文件事件（截断/重命名）
    private func handleLogFileEvent(fd: Int32, expanded: String) {
        if fileWatcher != nil {
            stop()
            watchAstrBotLogFile(expanded)
        }
    }

    /// 启动 docker logs 流（通过容器名）
    func startDockerLogStream(containerName: String, source: LogSource) {
        startContainerLogStream(containerName: containerName, source: source)
    }

    /// 启动指定容器的日志流
    func startContainerLogStream(containerName: String, source: LogSource) {
        stop()
        setupAccumulator()

        guard let proc = ContainerController.logs(containerName: containerName, tail: 500) else {
            append(.init(timestamp: Date(), level: .error, source: source, content: "无法启动 docker logs"))
            return
        }

        do {
            try proc.run()
        } catch {
            append(.init(timestamp: Date(), level: .error, source: source, content: "启动失败: \(error.localizedDescription)"))
            return
        }

        dockerProcess = proc
        isStreaming = true

        // 用非 actor 包装类 + 行缓冲
        let parser = LineParser()
        let acc = accumulator!
        let reader = DockerLogReader(
            process: proc,
            onLines: { rawStrings in
                // 后台线程：行切分
                var allLines: [String] = []
                for raw in rawStrings {
                    if raw.isEmpty { continue }
                    let parsed = parser.feed(Data(raw.utf8))
                    allLines.append(contentsOf: parsed)
                }
                if !allLines.isEmpty {
                    // 检测 WebUI URL（NapCat）
                    for line in allLines {
                        if let url = WebUIURLDetector.extract(from: line, for: .napcat) {
                            NotificationCenter.default.post(
                                name: .webUIDetected,
                                object: nil,
                                userInfo: ["source": LogSource.napcat, "url": url]
                            )
                        }
                    }
                    let now = Date()
                    let entries: [LogLine] = allLines.map { line in
                        LogLine(
                            timestamp: now,
                            level: LogLevel.detect(from: line),
                            source: source,
                            content: line
                        )
                    }
                    // 直接累积，无 Task 调度
                    acc.appendBatch(entries)
                }
            },
            onEOF: { [weak self] in
                let remaining = parser.flushRemaining()
                if let remaining {
                    let entry = LogLine(
                        timestamp: Date(),
                        level: LogLevel.detect(from: remaining),
                        source: source,
                        content: remaining
                    )
                    acc.appendBatch([entry])
                }
                Task { @MainActor [weak self] in
                    self?.isStreaming = false
                }
            }
        )
        reader.start()
        self.dockerReader = reader

        append(.init(timestamp: Date(), level: .debug, source: source, content: "已连接到容器日志: \(containerName)"))
    }

    /// 读取文件最后 N 行
    private func readLastLines(_ path: String, count: Int) {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize: UInt64 = 65536
        let offset = fileSize > readSize ? fileSize - readSize : 0
        try? handle.seek(toOffset: offset)
        let data = handle.readData(ofLength: Int(fileSize - offset))
        guard let str = String(data: data, encoding: .utf8) else { return }

        let allLines = str.split(separator: "\n", omittingEmptySubsequences: true)
        let lastLines = allLines.suffix(count)

        for line in lastLines {
            // 顺便检测历史日志中的 WebUI URL（文件已存在的部分）
            if let url = WebUIURLDetector.extract(from: String(line), for: .astrbot) {
                NotificationCenter.default.post(
                    name: .webUIDetected,
                    object: nil,
                    userInfo: ["source": LogSource.astrbot, "url": url]
                )
            }
            append(.init(
                timestamp: Date(),
                level: LogLevel.detect(from: String(line)),
                source: .astrbot,
                content: String(line)
            ))
        }
    }

    /// 设置 background 累积器 + Timer
    private func setupAccumulator() {
        let acc = BackgroundLogAccumulator(maxBufferSize: 2000, flushInterval: 1.0)
        // Timer 在主线程触发，每秒一次
        acc.onFlush = { [weak self] batch in
            guard let self else { return }
            // 暂停时丢弃新行（保留已显示的历史）
            if self.isPaused { return }
            // 一次性插入整批
            if batch.isEmpty { return }
            self.lines.append(contentsOf: batch)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
        }
        acc.start()
        self.accumulator = acc
    }

    /// 添加一行（用于初始化消息等）
    private func append(_ line: LogLine) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}
