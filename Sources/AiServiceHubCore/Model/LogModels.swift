import Foundation

/// 日志级别
public enum LogLevel: String, Sendable, Hashable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    /// 从一行文本推断级别
    public static func detect(from line: String) -> LogLevel {
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

/// 一行日志
public struct LogLine: Identifiable, Sendable, Hashable {

    /// 单行内容的存储上限（字符数）
    ///
    /// 有些服务会把整个请求 dump 进一行 —— AstrBot 的
    /// `anthropic._base_client` DEBUG 日志会把系统提示词连同全部工具定义
    /// 一并打出来，**单行能到 1.3 MB**（实测 `~/data/logs/astrbot.log`
    /// 共 10.8 MB / 1235 行，最长的几行都是 1.3 MB）。
    ///
    /// 不截断的后果有两个：
    /// - SwiftUI 渲染不了这么大的 `Text`，日志面板会变成**一片空白**
    ///   （行还在、背景还在，就是没有字）；
    /// - 2000 行的环形缓冲会吃掉 2.6 GB 内存。
    ///
    /// 2000 字符能覆盖 95% 以上的正常日志行（中位数 145 字节，p90 579 字节）。
    public static let maxContentLength = 2000

    /// 截断超长的一行
    public static func truncateContent(_ content: String) -> String {
        guard content.count > maxContentLength else { return content }
        let head = content.prefix(maxContentLength)
        return String(head) + "…（已截断，原文 \(content.count) 字符）"
    }

    public let id: UUID
    /// 在所属来源内单调递增的序号，用于订阅游标
    public let sequence: Int
    public let timestamp: Date
    public let level: LogLevel
    public let serviceID: UUID
    public let sourceID: String
    public let content: String

    public init(
        id: UUID = UUID(),
        sequence: Int,
        timestamp: Date = Date(),
        level: LogLevel,
        serviceID: UUID,
        sourceID: String,
        content: String
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.level = level
        self.serviceID = serviceID
        self.sourceID = sourceID
        self.content = content
    }
}

/// 日志来源类型
public enum LogSourceKind: Sendable, Hashable {
    /// 跟随文件尾部
    case file(path: String)
    /// 跟随一组文件中的最新一个（glob，例如 `~/.dsh/logs/startup-*.log`）
    case filePattern(pattern: String)
    /// 跟随子进程的标准输出
    case command(executable: String, arguments: [String])
    /// 轮询采集 Docker 容器日志
    ///
    /// 不用 `docker logs -f` 的原因：
    /// - `-f` 只输出**新**日志，不回放历史 —— 容器启动时打印的 WebUI 地址会被错过
    /// - `-f` 的进程在容器重启后退出，日志流就断了
    ///
    /// 改为按 `--since <时间戳>` 轮询：首次用 `--tail` 取历史，之后取增量。
    case dockerLogs(containerName: String)
}

/// 一个日志来源
public struct LogSourceSpec: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var label: String
    public var kind: LogSourceKind
    /// 该来源里用哪种规则提取 WebUI 地址（含 token）
    public var webUIKind: WebUIKind?

    public init(id: String, label: String, kind: LogSourceKind, webUIKind: WebUIKind? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.webUIKind = webUIKind
    }

    public static func file(id: String, label: String, path: String, webUIKind: WebUIKind? = nil) -> LogSourceSpec {
        LogSourceSpec(id: id, label: label, kind: .file(path: path), webUIKind: webUIKind)
    }

    public static func filePattern(id: String, label: String, pattern: String, webUIKind: WebUIKind? = nil) -> LogSourceSpec {
        LogSourceSpec(id: id, label: label, kind: .filePattern(pattern: pattern), webUIKind: webUIKind)
    }

    public static func command(id: String, label: String, executable: String, arguments: [String], webUIKind: WebUIKind? = nil) -> LogSourceSpec {
        LogSourceSpec(id: id, label: label, kind: .command(executable: executable, arguments: arguments), webUIKind: webUIKind)
    }

    public static func dockerLogs(id: String, label: String, containerName: String, webUIKind: WebUIKind? = nil) -> LogSourceSpec {
        LogSourceSpec(id: id, label: label, kind: .dockerLogs(containerName: containerName), webUIKind: webUIKind)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case path
        case pattern
        case executable
        case arguments
        case containerName
        case webUIKind
    }

    private enum Kind: String, Codable {
        case file
        case filePattern
        case command
        case dockerLogs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        webUIKind = try container.decodeIfPresent(WebUIKind.self, forKey: .webUIKind)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .file:
            kind = .file(path: try container.decode(String.self, forKey: .path))
        case .filePattern:
            kind = .filePattern(pattern: try container.decode(String.self, forKey: .pattern))
        case .command:
            kind = .command(
                executable: try container.decode(String.self, forKey: .executable),
                arguments: try container.decode([String].self, forKey: .arguments)
            )
        case .dockerLogs:
            kind = .dockerLogs(
                containerName: try container.decode(String.self, forKey: .containerName)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(webUIKind, forKey: .webUIKind)
        switch kind {
        case .file(let path):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .filePattern(let pattern):
            try container.encode(Kind.filePattern, forKey: .kind)
            try container.encode(pattern, forKey: .pattern)
        case .command(let executable, let arguments):
            try container.encode(Kind.command, forKey: .kind)
            try container.encode(executable, forKey: .executable)
            try container.encode(arguments, forKey: .arguments)
        case .dockerLogs(let containerName):
            try container.encode(Kind.dockerLogs, forKey: .kind)
            try container.encode(containerName, forKey: .containerName)
        }
    }
}
