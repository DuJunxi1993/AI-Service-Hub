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
    /// 跟随子进程的标准输出
    case command(executable: String, arguments: [String])
}

/// 一个日志来源
public struct LogSourceSpec: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var label: String
    public var kind: LogSourceKind

    public init(id: String, label: String, kind: LogSourceKind) {
        self.id = id
        self.label = label
        self.kind = kind
    }

    public static func file(id: String, label: String, path: String) -> LogSourceSpec {
        LogSourceSpec(id: id, label: label, kind: .file(path: path))
    }

    public static func command(id: String, label: String, executable: String, arguments: [String]) -> LogSourceSpec {
        LogSourceSpec(id: id, label: label, kind: .command(executable: executable, arguments: arguments))
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case path
        case executable
        case arguments
    }

    private enum Kind: String, Codable {
        case file
        case command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .file:
            kind = .file(path: try container.decode(String.self, forKey: .path))
        case .command:
            kind = .command(
                executable: try container.decode(String.self, forKey: .executable),
                arguments: try container.decode([String].self, forKey: .arguments)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        switch kind {
        case .file(let path):
            try container.encode(Kind.file, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .command(let executable, let arguments):
            try container.encode(Kind.command, forKey: .kind)
            try container.encode(executable, forKey: .executable)
            try container.encode(arguments, forKey: .arguments)
        }
    }
}
