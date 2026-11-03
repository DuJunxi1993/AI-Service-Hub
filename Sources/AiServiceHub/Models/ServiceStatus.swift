import SwiftUI

/// 服务运行状态
enum ServiceStatus: String, Codable, Equatable, Hashable {
    case unknown     // 未探测
    case stopped     // 已停止
    case starting    // 启动中
    case running     // 运行中
    case stopping    // 停止中
    case error       // 错误

    var displayName: String {
        switch self {
        case .unknown: return "未知"
        case .stopped: return "已停止"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .error: return "异常"
        }
    }

    /// 状态点颜色
    var color: Color {
        switch self {
        case .unknown: return Color.gray.opacity(0.5)
        case .stopped: return Color.gray
        case .starting, .stopping: return Color.orange
        case .running: return Color.green
        case .error: return Color.red
        }
    }

    /// 是否处于过渡态
    var isTransitional: Bool {
        self == .starting || self == .stopping
    }

    /// 是否可启动
    var canStart: Bool {
        self == .stopped || self == .error || self == .unknown
    }

    /// 是否可停止
    var canStop: Bool {
        self == .running || self == .starting
    }
}
