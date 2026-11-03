import Foundation

/// 探测方式
public enum Probe: Codable, Sendable, Hashable {
    /// 命令行匹配（pgrep -f）
    case processPattern(String)
    /// TCP 端口监听
    case tcpPort(Int)
    /// HTTP 可达（401 也算可达 —— 用于需要鉴权的服务）
    case httpReachability(String)
    /// 文件存在
    case fileExists(String)
    /// JSON 文件里的某个字段
    case jsonState(path: String, key: String)
    /// Hermes Gateway 状态文件
    case hermesGateway(path: String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case path
        case key
        case port
    }

    private enum Kind: String, Codable {
        case processPattern
        case tcpPort
        case httpReachability
        case fileExists
        case jsonState
        case hermesGateway
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .processPattern:
            self = .processPattern(try container.decode(String.self, forKey: .value))
        case .tcpPort:
            self = .tcpPort(try container.decode(Int.self, forKey: .port))
        case .httpReachability:
            self = .httpReachability(try container.decode(String.self, forKey: .value))
        case .fileExists:
            self = .fileExists(try container.decode(String.self, forKey: .value))
        case .jsonState:
            self = .jsonState(
                path: try container.decode(String.self, forKey: .path),
                key: try container.decode(String.self, forKey: .key)
            )
        case .hermesGateway:
            self = .hermesGateway(path: try container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .processPattern(let value):
            try container.encode(Kind.processPattern, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .tcpPort(let port):
            try container.encode(Kind.tcpPort, forKey: .kind)
            try container.encode(port, forKey: .port)
        case .httpReachability(let value):
            try container.encode(Kind.httpReachability, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .fileExists(let value):
            try container.encode(Kind.fileExists, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .jsonState(let path, let key):
            try container.encode(Kind.jsonState, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(key, forKey: .key)
        case .hermesGateway(let path):
            try container.encode(Kind.hermesGateway, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }

    /// 展示用的标签
    public var label: String {
        switch self {
        case .processPattern: return "进程"
        case .tcpPort(let port): return "端口 \(port)"
        case .httpReachability: return "HTTP 可达性"
        case .fileExists: return "文件"
        case .jsonState(_, let key): return "状态 \(key)"
        case .hermesGateway: return "Gateway"
        }
    }
}

/// 单项探测结果的状态
public enum ProbeState: String, Sendable, Hashable {
    case ok
    case warning
    case failed
    case unknown
}

/// 探测结果里的一行明细
public struct DetailRow: Sendable, Hashable, Identifiable {
    public var id: String { label }
    public let label: String
    public let value: String
    public let state: ProbeState?
    /// 补充说明（例如「3 分钟前」），不影响状态着色
    public let note: String?

    public init(label: String, value: String, state: ProbeState? = nil, note: String? = nil) {
        self.label = label
        self.value = value
        self.state = state
        self.note = note
    }
}

/// 探测结果的分组明细
public struct DetailGroup: Sendable, Hashable, Identifiable {
    public var id: String { title }
    public let title: String
    public let rows: [DetailRow]

    public init(title: String, rows: [DetailRow]) {
        self.title = title
        self.rows = rows
    }
}

/// 一次探测的结果
public struct ProbeResult: Sendable, Hashable, Identifiable {
    public var id: String { label }
    public let label: String
    public let state: ProbeState
    public let summary: String
    public let groups: [DetailGroup]

    public init(label: String, state: ProbeState, summary: String, groups: [DetailGroup] = []) {
        self.label = label
        self.state = state
        self.summary = summary
        self.groups = groups
    }
}
