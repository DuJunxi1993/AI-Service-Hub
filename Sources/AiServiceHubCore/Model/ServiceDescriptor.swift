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
        note: String? = nil
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
}
