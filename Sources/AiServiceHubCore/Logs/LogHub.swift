import Foundation

/// 日志中心
///
/// 每个服务可以配置多个日志来源，Hub 为每个来源维持：
/// - 一个**常驻**的 tailer（与界面无关，切换服务不会中断采集）
/// - 一个环形缓冲（默认 2000 行）
/// - 若干订阅者（`AsyncStream`）
///
/// WebUI 地址的提取也在这里完成 —— 它是日志的**消费者**，
/// 而不是「用户恰好选中了那个服务」的副作用。
public actor LogHub {
    public struct SourceKey: Hashable, Sendable {
        public let serviceID: UUID
        public let sourceID: String
    }

    private struct SourceState {
        /// 来源规格（跟随器按需创建）
        var spec: LogSourceSpec
        /// 常驻跟随器 —— **只在有人订阅日志时才存在**
        var tailer: LogTailer?
        var buffer: [LogLine] = []
        var sequence: Int = 0
        var webUIKind: WebUIKind?
        /// 缓冲占用的字节数（估算），用于按字节淘汰
        var bytes: Int = 0
    }

    private let bufferLimit: Int
    /// 单个来源的缓冲字节上限
    ///
    /// 行数上限本身挡不住内存：`LogLine.maxContentLength` 之后一行最多 2000 字符，
    /// 2000 行仍然可能有几 MB，再乘以来源数就上不封顶了。这里再加一道字节闸。
    private let bufferByteLimit: Int
    private var sources: [SourceKey: SourceState] = [:]
    private var subscribers: [SourceKey: [UUID: AsyncStream<[LogLine]>.Continuation]] = [:]
    /// 每个服务的订阅者数量 —— 归零时停止跟随
    private var subscriberCounts: [UUID: Int] = [:]
    private var webURLs: [UUID: URL] = [:]

    public init(bufferLimit: Int = 2000, bufferByteLimit: Int = 4 * 1024 * 1024) {
        self.bufferLimit = bufferLimit
        self.bufferByteLimit = bufferByteLimit
    }

    // MARK: - 订阅

    /// 订阅某个服务的所有来源
    ///
    /// 返回的流会先吐出已有的历史，再持续推送新行。
    public func subscribe(serviceID: UUID) -> AsyncStream<[LogLine]> {
        let key = SourceKey(serviceID: serviceID, sourceID: "*")
        let id = UUID()

        return AsyncStream { continuation in
            for sourceKey in sourceKeys(for: serviceID) {
                subscribers[sourceKey, default: [:]][id] = continuation
            }
            subscriberCounts[serviceID, default: 0] += 1
            // 第一个订阅者 → 开始跟随（历史也会顺着这条流推下来）
            if subscriberCounts[serviceID] == 1 {
                startTailing(serviceID: serviceID)
            }
            let existing = allBufferedLines(serviceID: serviceID)
            if !existing.isEmpty {
                continuation.yield(existing)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id: id, serviceID: serviceID) }
            }
        }
    }

    private func removeSubscriber(id: UUID, serviceID: UUID) {
        for sourceKey in sourceKeys(for: serviceID) {
            subscribers[sourceKey]?[id] = nil
            if subscribers[sourceKey]?.isEmpty == true {
                subscribers[sourceKey] = nil
            }
        }
        let remaining = max(0, (subscriberCounts[serviceID] ?? 0) - 1)
        subscriberCounts[serviceID] = remaining
        // 没人看了 → 停掉跟随，别在后台空转
        if remaining == 0 {
            stopTailing(serviceID: serviceID)
        }
    }

    /// 取某个服务当前的全部日志行
    public func history(serviceID: UUID) -> [LogLine] {
        allBufferedLines(serviceID: serviceID)
    }

    private func allBufferedLines(serviceID: UUID) -> [LogLine] {
        sourceKeys(for: serviceID)
            .compactMap { sources[$0]?.buffer }
            .flatMap { $0 }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - 来源管理

    /// 登记一个服务的所有日志来源
    ///
    /// **只登记，不开始跟随** —— 跟随器是按需创建的：
    /// 本程序本质上是个**查看器**，日志只有在用户打开日志面板时才有意义。
    /// 没有订阅者时不该在后台每秒 stat 文件、每两秒起一个 docker 进程。
    public func attach(descriptor: ServiceDescriptor) {
        for spec in descriptor.logSources {
            let key = SourceKey(serviceID: descriptor.id, sourceID: spec.id)
            guard sources[key] == nil else { continue }
            sources[key] = SourceState(spec: spec, webUIKind: spec.webUIKind)
        }
    }

    /// 开始跟随某个服务的所有来源
    private func startTailing(serviceID: UUID) {
        for key in sourceKeys(for: serviceID) {
            guard var state = sources[key], state.tailer == nil else { continue }

            let webUIKind = state.webUIKind
            let label = state.spec.label
            let tailer = LogTailer(spec: state.spec) { [weak self] lines in
                Task { await self?.ingest(lines: lines, key: key, webUIKind: webUIKind) }
            } onStateChange: { _ in }

            state.tailer = tailer
            sources[key] = state
            tailer.start()
            AppLog.info("开始跟随日志：\(label)")
        }
    }

    /// 停止跟随某个服务的所有来源
    ///
    /// 缓冲一并清掉：跟随器重启时会重新吐出历史，
    /// 留着旧缓冲只会让同一段日志出现两遍。
    private func stopTailing(serviceID: UUID) {
        for key in sourceKeys(for: serviceID) {
            guard var state = sources[key] else { continue }
            state.tailer?.stop()
            state.tailer = nil
            state.buffer = []
            state.bytes = 0
            sources[key] = state
        }
        AppLog.info("停止跟随日志（已无订阅者）")
    }

    /// 停止某个服务的所有日志来源
    public func detach(serviceID: UUID) {
        for key in sourceKeys(for: serviceID) {
            sources[key]?.tailer?.stop()
            sources[key] = nil
            subscribers[key] = nil
        }
        subscriberCounts[serviceID] = nil
    }

    /// 一次性扫描历史，找出服务的 WebUI 地址
    ///
    /// 「打开 WebUI」按钮不能等用户打开日志面板才有地址可用
    /// （NapCat 的地址带 token，只存在于容器日志里），所以这里单独扫一次 ——
    /// 只读一次历史，不建立常驻跟随。
    public func probeWebUIURL(for descriptor: ServiceDescriptor) {
        for spec in descriptor.logSources {
            guard let kind = spec.webUIKind else { continue }
            let tailer = LogTailer(spec: spec) { _ in } onStateChange: { _ in }
            for line in tailer.readHistoryLines() {
                if let url = WebUIURLDetector.extract(from: line, for: kind) {
                    if webURLs[descriptor.id] != url {
                        AppLog.info("探测到 WebUI 地址（\(spec.label)）：\(url.absoluteString)")
                    }
                    webURLs[descriptor.id] = url
                    break
                }
            }
        }
    }

    /// 移除服务（同时清理 WebUI 地址）
    public func removeService(serviceID: UUID) {
        detach(serviceID: serviceID)
        webURLs[serviceID] = nil
    }

    /// 服务当前解析到的 WebUI 地址
    public func webURL(for serviceID: UUID) -> URL? {
        webURLs[serviceID]
    }

    /// 手动设置 WebUI 地址（兜底，例如从 compose 解析出来的端口）
    public func setWebURL(_ url: URL?, for serviceID: UUID) {
        webURLs[serviceID] = url
    }

    // MARK: - 内部

    private func sourceKeys(for serviceID: UUID) -> [SourceKey] {
        sources.keys.filter { $0.serviceID == serviceID }.sorted { $0.sourceID < $1.sourceID }
    }

    private func ingest(lines: [String], key: SourceKey, webUIKind: WebUIKind?) {
        guard !lines.isEmpty else { return }
        guard var state = sources[key] else { return }

        let now = Date()
        var batch: [LogLine] = []
        batch.reserveCapacity(lines.count)

        for line in lines {
            state.sequence += 1
            // 级别判定用**原始**行（关键字可能在行尾），存储时才截断。
            // WebUI 地址提取同样用原始行（见下方），不受截断影响。
            let content = LogLine.truncateContent(line)
            batch.append(LogLine(
                sequence: state.sequence,
                timestamp: now,
                level: LogLevel.detect(from: line),
                serviceID: key.serviceID,
                sourceID: key.sourceID,
                content: content
            ))
            state.bytes += content.utf8.count
        }

        state.buffer.append(contentsOf: batch)
        // 按行数淘汰
        if state.buffer.count > bufferLimit {
            let drop = state.buffer.count - bufferLimit
            state.bytes -= state.buffer.prefix(drop).reduce(0) { $0 + $1.content.utf8.count }
            state.buffer.removeFirst(drop)
        }
        // 再按字节淘汰（单行超长时行数上限挡不住）
        while state.bytes > bufferByteLimit, !state.buffer.isEmpty {
            let dropped = state.buffer.removeFirst()
            state.bytes -= dropped.content.utf8.count
        }
        sources[key] = state

        // 推送
        for continuation in (subscribers[key]?.values ?? [:].values) {
            continuation.yield(batch)
        }

        // 提取 WebUI 地址
        // 取批次里**最后**出现的那个：容器重启后 token 可能变化，
        // 而日志行是按时间顺序的，越靠后越新。
        if let webUIKind {
            var extracted: URL?
            for line in lines {
                if let url = WebUIURLDetector.extract(from: line, for: webUIKind) {
                    extracted = url
                }
            }
            if let url = extracted {
                if webURLs[key.serviceID] != url {
                    AppLog.info("解析到 WebUI 地址（\(key.sourceID)）：\(url.absoluteString)")
                }
                webURLs[key.serviceID] = url
            }
        }
    }
}
