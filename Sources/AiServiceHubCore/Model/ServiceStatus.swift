import Foundation

/// 服务运行状态
public enum ServiceStatus: String, Codable, Sendable, Hashable {
    case unknown      // 未探测
    case stopped      // 已停止
    case starting     // 启动中
    case running      // 运行中
    case stopping     // 停止中
    case degraded     // 部分可用（例如某个平台断开）
    case error        // 异常

    public var displayName: String {
        switch self {
        case .unknown: return "未知"
        case .stopped: return "已停止"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .degraded: return "部分可用"
        case .error: return "异常"
        }
    }

    /// 是否处于过渡态
    public var isTransitional: Bool {
        self == .starting || self == .stopping
    }

    /// 是否可启动
    public var canStart: Bool {
        self == .stopped || self == .error || self == .unknown
    }

    /// 是否可停止
    public var canStop: Bool {
        self == .running || self == .starting || self == .degraded
    }
}
