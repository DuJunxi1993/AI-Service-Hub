import Foundation
import SwiftUI
import AiServiceHubCore

/// 应用设置
///
/// 持久化在 `~/Library/Application Support/AI Service Hub/config.json`。
/// 首次启动时若检测到旧版（`com.djx.astrbotlauncher` 域）的配置，会自动迁移过来。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store: ConfigStore
    private(set) var config: AppConfig

    /// 迁移提示（一次性）
    @Published var migrationNotice: String?

    // MARK: - 偏好

    @Published var themeMode: ThemeMode {
        didSet { syncPreferences() }
    }

    @Published var pollingInterval: Int {
        didSet { syncPreferences() }
    }

    @Published var enableNotifications: Bool {
        didSet { syncPreferences() }
    }

    @Published var startMinimized: Bool {
        didSet { syncPreferences() }
    }

    @Published var autoStartOnBoot: Bool {
        didSet { syncPreferences() }
    }

    /// 启动时自动拉起服务（总开关，配合每个服务自己的 autoStart）
    @Published var autoStartAllServices: Bool {
        didSet { syncPreferences() }
    }

    // MARK: - 服务集合

    /// 所有已登记的服务
    @Published var services: [ServiceDescriptor] {
        didSet { persist() }
    }

    /// 侧边栏顺序
    @Published var sidebarOrder: [UUID] {
        didSet { syncPreferences() }
    }

    /// 当前选中的服务
    @Published var selectedServiceID: UUID? {
        didSet { syncPreferences() }
    }

    // MARK: - 初始化

    init(store: ConfigStore = ConfigStore()) {
        self.store = store

        let loaded = store.load()
        var initial: AppConfig

        if let loaded {
            initial = loaded
        } else if LegacyMigration.hasLegacyData() {
            initial = LegacyMigration.migrate()
            AppLog.info("已从旧版配置迁移：\(initial.services.count) 个服务")
            migrationNotice = "已从旧版 AstrBot Launcher 的配置自动迁移"
        } else {
            initial = AppConfig(
                preferences: Preferences(),
                services: Self.defaultDescriptors(),
                ownedProcesses: []
            )
        }

        // 升级旧配置（容器日志源、webUIKind 等）
        initial.upgradeLogSources()
        config = initial

        let preferences = initial.preferences
        themeMode = preferences.themeMode
        pollingInterval = preferences.pollingIntervalSeconds
        enableNotifications = preferences.enableNotifications
        startMinimized = preferences.startMinimized
        autoStartOnBoot = preferences.loginItemEnabled
        autoStartAllServices = preferences.autoStartAllServices
        services = initial.services
        sidebarOrder = preferences.sidebarOrder.isEmpty
            ? initial.services.map(\.id)
            : preferences.sidebarOrder
        selectedServiceID = preferences.selectedServiceID

        // 首次启动：把内置预设补进去
        ensureBuiltinPresets()
    }

    /// 出厂默认服务集合
    static func defaultDescriptors() -> [ServiceDescriptor] {
        [
            AstrBotPreset.makeDescriptor(),
            HermesPreset.makeDescriptor(),
            DSHPreset.makeDescriptor()
        ]
    }

    /// 内置预设
    static func builtinPresets() -> [ServiceDescriptor] {
        [
            AstrBotPreset.makeDescriptor(),
            HermesPreset.makeDescriptor(),
            DSHPreset.makeDescriptor()
        ]
    }

    /// 确保内置预设存在
    ///
    /// 已被用户主动移除的预设（记录在 `dismissedPresetIDs`）不会被装回。
    private func ensureBuiltinPresets() {
        let installed = Set(services.compactMap(\.presetIdentifier))
        let dismissed = Set(config.preferences.dismissedPresetIDs)

        var added: [ServiceDescriptor] = []
        for preset in Self.builtinPresets() {
            guard let identifier = preset.presetIdentifier else { continue }
            guard !installed.contains(identifier) else { continue }
            guard !dismissed.contains(identifier) else { continue }
            added.append(preset)
        }
        guard !added.isEmpty else { return }
        services.append(contentsOf: added)
        sidebarOrder.append(contentsOf: added.map(\.id))
        AppLog.info("已安装内置预设：\(added.map(\.name).joined(separator: ", "))")
    }

    /// 恢复全部内置预设（清空移除记录）
    func restoreBuiltinPresets() {
        config.preferences.dismissedPresetIDs = []
        persist()
        ensureBuiltinPresets()
    }

    // MARK: - 查询

    /// 按侧边栏顺序排列的服务
    var orderedServices: [ServiceDescriptor] {
        let order = sidebarOrder
        let known = order.compactMap { id in services.first { $0.id == id } }
        let remaining = services.filter { !order.contains($0.id) }
        return known + remaining
    }

    /// 参与「启动时自动拉起」的服务
    var autoStartServices: [ServiceDescriptor] {
        guard autoStartAllServices else { return [] }
        return orderedServices.filter { $0.participatesInAutoStart }
    }

    func service(id: UUID) -> ServiceDescriptor? {
        services.first { $0.id == id }
    }

    func service(named name: String) -> ServiceDescriptor? {
        services.first { $0.name == name }
    }

    /// 展开路径中的 ~
    func expandPath(_ path: String) -> String {
        PathExpander.expand(path)
    }

    // MARK: - 修改

    /// 更新一个服务
    func update(_ descriptor: ServiceDescriptor) {
        guard let index = services.firstIndex(where: { $0.id == descriptor.id }) else { return }
        services[index] = descriptor
    }

    /// 添加一个服务
    func add(_ descriptor: ServiceDescriptor) {
        services.append(descriptor)
        sidebarOrder.append(descriptor.id)
    }

    /// 删除一个服务
    ///
    /// 如果是内置预设，记录到 `dismissedPresetIDs`，避免下次启动又被装回来。
    func remove(id: UUID) {
        if let descriptor = services.first(where: { $0.id == id }),
           let presetIdentifier = descriptor.presetIdentifier,
           !config.preferences.dismissedPresetIDs.contains(presetIdentifier) {
            config.preferences.dismissedPresetIDs.append(presetIdentifier)
        }
        services.removeAll { $0.id == id }
        sidebarOrder.removeAll { $0 == id }
        if selectedServiceID == id {
            selectedServiceID = orderedServices.first?.id
        }
        persist()
    }

    /// 调整侧边栏顺序
    func moveServices(from offsets: IndexSet, to destination: Int) {
        var ordered = orderedServices
        ordered.move(fromOffsets: offsets, toOffset: destination)
        sidebarOrder = ordered.map(\.id)
    }

    // MARK: - 持久化

    private func syncPreferences() {
        config.preferences.themeMode = themeMode
        config.preferences.pollingIntervalSeconds = pollingInterval
        config.preferences.enableNotifications = enableNotifications
        config.preferences.startMinimized = startMinimized
        config.preferences.loginItemEnabled = autoStartOnBoot
        config.preferences.autoStartAllServices = autoStartAllServices
        config.preferences.sidebarOrder = sidebarOrder
        config.preferences.selectedServiceID = selectedServiceID
        persist()
    }

    private func persist() {
        config.services = services
        config.preferences.sidebarOrder = sidebarOrder
        config.preferences.selectedServiceID = selectedServiceID
        config.preferences.themeMode = themeMode
        config.preferences.pollingIntervalSeconds = pollingInterval
        config.preferences.enableNotifications = enableNotifications
        config.preferences.startMinimized = startMinimized
        config.preferences.loginItemEnabled = autoStartOnBoot
        config.preferences.autoStartAllServices = autoStartAllServices
        store.save(config)
    }

    // MARK: - 所有权账本

    /// 某个服务当前持有的进程记录
    func ledgerRecord(for serviceID: UUID) -> OwnedProcessRecord? {
        config.ownedProcesses.first { $0.serviceID == serviceID }
    }

    /// 写入 / 更新所有权记录
    func upsertLedgerRecord(_ record: OwnedProcessRecord) {
        if let index = config.ownedProcesses.firstIndex(where: { $0.serviceID == record.serviceID }) {
            config.ownedProcesses[index] = record
        } else {
            config.ownedProcesses.append(record)
        }
        store.save(config)
    }

    /// 移除所有权记录
    func removeLedgerRecord(serviceID: UUID) {
        config.ownedProcesses.removeAll { $0.serviceID == serviceID }
        store.save(config)
    }

    /// 全部所有权记录
    var ledgerRecords: [OwnedProcessRecord] {
        config.ownedProcesses
    }

    /// 覆盖全部所有权记录
    func replaceLedgerRecords(_ records: [OwnedProcessRecord]) {
        config.ownedProcesses = records
        store.save(config)
    }

    /// 回收上次非正常退出留下的孤儿进程，并写回账本
    /// - Returns: 被终止的 pid
    @discardableResult
    func reclaimOrphanProcesses(using ledger: OwnershipLedger) async -> [Int32] {
        var records = config.ownedProcesses
        let terminated = await ledger.reclaimOrphans(in: &records)
        config.ownedProcesses = records
        store.save(config)
        return terminated
    }

    /// 恢复出厂设置
    func resetToDefaults() {
        store.reset()
        config = AppConfig(
            preferences: Preferences(),
            services: Self.defaultDescriptors(),
            ownedProcesses: []
        )
        services = config.services
        sidebarOrder = config.services.map(\.id)
        selectedServiceID = nil
        themeMode = .system
        pollingInterval = 5
        enableNotifications = true
        startMinimized = false
        autoStartOnBoot = false
        autoStartAllServices = true
        store.save(config)
    }
}
