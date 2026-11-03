import Foundation

/// 主题模式
public enum ThemeMode: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    public var id: String { rawValue }

    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// 全局偏好
public struct Preferences: Codable, Sendable, Equatable {
    public var themeMode: ThemeMode
    /// 状态轮询间隔（秒）
    public var pollingIntervalSeconds: Int
    /// 服务启停时发送系统通知
    public var enableNotifications: Bool
    /// 启动时最小化到 Dock
    public var startMinimized: Bool
    /// 注册为登录项
    public var loginItemEnabled: Bool
    /// 启动时自动拉起服务（总开关，配合每个服务自己的 autoStart）
    public var autoStartAllServices: Bool
    /// 侧边栏顺序（服务 id）
    public var sidebarOrder: [UUID]
    /// 当前选中的服务
    public var selectedServiceID: UUID?

    public init(
        themeMode: ThemeMode = .system,
        pollingIntervalSeconds: Int = 5,
        enableNotifications: Bool = true,
        startMinimized: Bool = false,
        loginItemEnabled: Bool = false,
        autoStartAllServices: Bool = true,
        sidebarOrder: [UUID] = [],
        selectedServiceID: UUID? = nil
    ) {
        self.themeMode = themeMode
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.enableNotifications = enableNotifications
        self.startMinimized = startMinimized
        self.loginItemEnabled = loginItemEnabled
        self.autoStartAllServices = autoStartAllServices
        self.sidebarOrder = sidebarOrder
        self.selectedServiceID = selectedServiceID
    }
}

/// 本程序持有的进程记录
///
/// 用于两件事：
/// 1. 判定「这个 pid 还是不是本程序当初启动的那个」（避免 PID 复用导致误杀）
/// 2. launcher 被强杀 / 崩溃后，下次启动回收 `detached == false` 的孤儿进程
public struct OwnedProcessRecord: Codable, Sendable, Equatable {
    public var serviceID: UUID
    public var pid: Int32
    /// 进程启动时间标识（sysctl 取到的 p_starttime）
    public var startTimeToken: String?
    public var executable: String
    public var arguments: [String]
    /// 是否 daemon 化
    public var detached: Bool

    public init(
        serviceID: UUID,
        pid: Int32,
        startTimeToken: String? = nil,
        executable: String,
        arguments: [String],
        detached: Bool
    ) {
        self.serviceID = serviceID
        self.pid = pid
        self.startTimeToken = startTimeToken
        self.executable = executable
        self.arguments = arguments
        self.detached = detached
    }
}

/// 应用配置
public struct AppConfig: Codable, Sendable, Equatable {
    /// 当前 schema 版本
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var preferences: Preferences
    /// 所有已登记的服务
    public var services: [ServiceDescriptor]
    /// 本程序持有的进程
    public var ownedProcesses: [OwnedProcessRecord]

    public init(
        schemaVersion: Int = AppConfig.currentSchemaVersion,
        preferences: Preferences = Preferences(),
        services: [ServiceDescriptor] = [],
        ownedProcesses: [OwnedProcessRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.preferences = preferences
        self.services = services
        self.ownedProcesses = ownedProcesses
    }

    /// 按 id 查找服务
    public func service(id: UUID) -> ServiceDescriptor? {
        services.first { $0.id == id }
    }

    /// 按 id 查找服务的下标
    public func indexOfService(id: UUID) -> Int? {
        services.firstIndex { $0.id == id }
    }
}
