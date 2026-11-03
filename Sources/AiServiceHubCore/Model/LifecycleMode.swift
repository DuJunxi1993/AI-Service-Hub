import Foundation

/// 生命周期模式
///
/// 顶层只回答一件事：**本程序要不要负责这个服务的生命周期**。
public enum LifecycleMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// 纯监控：只读取状态与日志，不启动、不停止、不持有任何进程
    case observed
    /// 可管理：由本程序负责启停
    case managed

    public var displayName: String {
        switch self {
        case .observed: return "纯监控"
        case .managed: return "可管理"
        }
    }

    public var summary: String {
        switch self {
        case .observed: return "只读取状态与日志，不接管进程"
        case .managed: return "由本程序负责启动与停止"
        }
    }
}

/// 可管理服务的驱动方式
public enum ManagedDriver: String, Codable, Sendable, Hashable, CaseIterable {
    /// 持有子进程：本程序 spawn 并持有 PID
    case process
    /// 委托容器：本程序只发 docker start/stop，进程由 dockerd 托管
    case container

    public var displayName: String {
        switch self {
        case .process: return "持有子进程"
        case .container: return "委托 Docker 容器"
        }
    }
}
