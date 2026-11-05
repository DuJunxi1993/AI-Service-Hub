import Foundation

/// 服务描述符 —— 系统中一个可被纳管的服务的完整定义
///
/// 描述符是**配置**（用户可编辑、可持久化），与运行时的 `ServiceSnapshot` 分离。
public struct ServiceDescriptor: Identifiable, Codable, Sendable, Hashable {
    /// 稳定标识
    public let id: UUID
    /// 显示名
    public var name: String
    /// 生命周期模式
    public var lifecycle: LifecycleMode
    /// 是否在侧边栏展示
    public var enabled: Bool
    /// 启动时是否自动拉起（仅对 `managed` 生效）
    public var autoStart: Bool
    /// 展示元数据
    public var appearance: Appearance
    /// 可管理配置（`lifecycle == .observed` 时为 nil）
    public var managed: ManagedSpec?
    /// 状态探测
    public var probes: [Probe]
    /// 日志来源
    public var logSources: [LogSourceSpec]
    /// 可选的「打开」入口（WebUI 等）
    public var openURL: URL?
    /// 备注
    public var note: String?
    /// 该服务的数据目录（「打开数据目录」按钮的目标）
    public var dataDirectory: String?
    /// 「停止全部进程」用的进程匹配模式
    ///
    /// 与 `probes` 里的探测模式分开：探测要**精确**（PID 决定了端口反查的对象），
    /// 而「停止全部」要**全面**（Hermes 的进程散落在 supervisor / python / 桌面端各处，
    /// 只按探测模式匹配会漏掉一大半）。
    public var stopProcessPatterns: [String]?
    /// 若该服务来自内置预设，记录预设标识（用于避免重复安装与支持「恢复预设」）
    public var presetIdentifier: String?

    public init(
        id: UUID = UUID(),
        name: String,
        lifecycle: LifecycleMode,
        enabled: Bool = true,
        autoStart: Bool = false,
        appearance: Appearance,
        managed: ManagedSpec? = nil,
        probes: [Probe] = [],
        logSources: [LogSourceSpec] = [],
        openURL: URL? = nil,
        note: String? = nil,
        dataDirectory: String? = nil,
        stopProcessPatterns: [String]? = nil,
        presetIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lifecycle = lifecycle
        self.enabled = enabled
        self.autoStart = autoStart
        self.appearance = appearance
        self.managed = managed
        self.probes = probes
        self.logSources = logSources
        self.openURL = openURL
        self.note = note
        self.dataDirectory = dataDirectory
        self.stopProcessPatterns = stopProcessPatterns
        self.presetIdentifier = presetIdentifier
    }

    /// 驱动方式（纯监控服务没有驱动）
    public var driver: ManagedDriver? {
        guard lifecycle == .managed else { return nil }
        return managed?.driver
    }

    /// 是否参与「启动时自动拉起」
    public var participatesInAutoStart: Bool {
        lifecycle == .managed && enabled && autoStart
    }

    /// 从 `old` 变到 `self` 时，要不要**立刻**把服务拉起来
    ///
    /// 「启动时自动拉起」原本只在 app 启动时跑一次。用户�� app 运行期间勾选这个框，
    /// 看上去毫无反应 —— 而服务可能刚好崩了正等着被拉起。
    /// 所以勾选即生效：可管理的服务被新勾上时，现在就启动它。
    public func shouldStartImmediately(comparedTo old: ServiceDescriptor) -> Bool {
        autoStart && !old.autoStart && lifecycle == .managed
    }

    /// 该服务相关的进程匹配模式（来自探测配置）
    ///
    /// 用于「停止全部相关进程」——纯监控服务没有驱动，
    /// 但用户仍可能想一键停掉它（例如 Hermes 网关）。
    public var processPatterns: [String] {
        probes.compactMap { probe in
            if case .processPattern(let pattern) = probe { return pattern }
            return nil
        }
    }

    /// 「停止全部进程」实际使用的模式
    public var effectiveStopPatterns: [String] {
        let explicit = stopProcessPatterns ?? []
        return explicit.isEmpty ? processPatterns : explicit
    }
}
