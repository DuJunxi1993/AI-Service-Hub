import Foundation
import SwiftUI

/// 持久化的应用设置
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store = UserDefaults.standard

    enum Key {
        static let astrBotLaunchMode = "astrBotLaunchMode"
        static let astrBotCustomCommand = "astrBotCustomCommand"
        static let astrBotExecutablePath = "astrBotExecutablePath"
        static let astrBotScriptPath = "astrBotScriptPath"
        static let astrBotWebPort = "astrBotWebPort"
        static let napcatContainer = "napcatContainer"
        static let shipyardContainer = "shipyardContainer"
        static let astrbotLogPath = "astrbotLogPath"
        static let dataDirectory = "dataDirectory"
        static let pollingInterval = "pollingInterval"
        static let autoStartOnBoot = "autoStartOnBoot"
        static let startMinimized = "startMinimized"
        static let autoStartAllServices = "autoStartAllServices"
        static let manualComposePaths = "manualComposePaths"
        static let themeMode = "themeMode"
        static let enableNotifications = "enableNotifications"
        static let selectedService = "selectedService"
        static let serviceOrder = "serviceOrder"
    }

    // MARK: - AstrBot
    @Published var astrBotLaunchMode: AstrBotLaunchMode {
        didSet { store.set(astrBotLaunchMode.rawValue, forKey: Key.astrBotLaunchMode) }
    }

    @Published var astrBotCustomCommand: String {
        didSet { store.set(astrBotCustomCommand, forKey: Key.astrBotCustomCommand) }
    }

    @Published var astrBotExecutablePath: String {
        didSet { store.set(astrBotExecutablePath, forKey: Key.astrBotExecutablePath) }
    }

    @Published var astrBotScriptPath: String {
        didSet { store.set(astrBotScriptPath, forKey: Key.astrBotScriptPath) }
    }

    @Published var astrBotWebPort: Int {
        didSet { store.set(astrBotWebPort, forKey: Key.astrBotWebPort) }
    }

    // MARK: - 容器
    @Published var napcatContainer: String {
        didSet { store.set(napcatContainer, forKey: Key.napcatContainer) }
    }

    @Published var shipyardContainer: String {
        didSet { store.set(shipyardContainer, forKey: Key.shipyardContainer) }
    }

    @Published var manualComposePaths: [String] {
        didSet { store.set(manualComposePaths, forKey: Key.manualComposePaths) }
    }

    @Published var selectedService: ServiceType {
        didSet { store.set(selectedService.rawValue, forKey: Key.selectedService) }
    }

    /// Sidebar 服务显示顺序（Finder 风格：按 displayName 字母排序）
    @Published var serviceOrder: [ServiceType] {
        didSet { store.set(serviceOrder.map { $0.rawValue }, forKey: Key.serviceOrder) }
    }

    // MARK: - Paths
    @Published var astrbotLogPath: String {
        didSet { store.set(astrbotLogPath, forKey: Key.astrbotLogPath) }
    }

    @Published var dataDirectory: String {
        didSet { store.set(dataDirectory, forKey: Key.dataDirectory) }
    }

    // MARK: - Behavior
    @Published var pollingInterval: Int {
        didSet { store.set(pollingInterval, forKey: Key.pollingInterval) }
    }

    @Published var autoStartOnBoot: Bool {
        didSet { store.set(autoStartOnBoot, forKey: Key.autoStartOnBoot) }
    }

    @Published var startMinimized: Bool {
        didSet { store.set(startMinimized, forKey: Key.startMinimized) }
    }

    /// 启动时自动运行全部服务（默认 true，对老用户首次启动生效）
    @Published var autoStartAllServices: Bool {
        didSet { store.set(autoStartAllServices, forKey: Key.autoStartAllServices) }
    }

    @Published var themeMode: ThemeMode {
        didSet { store.set(themeMode.rawValue, forKey: Key.themeMode) }
    }

    @Published var enableNotifications: Bool {
        didSet { store.set(enableNotifications, forKey: Key.enableNotifications) }
    }

    private init() {
        // 注册默认值：让老用户首次启动也能享受 autoStartAllServices = true
        store.register(defaults: [Key.autoStartAllServices: true])

        // AstrBot
        let modeRaw = store.string(forKey: Key.astrBotLaunchMode) ?? AstrBotLaunchMode.uvToolRun.rawValue
        self.astrBotLaunchMode = AstrBotLaunchMode(rawValue: modeRaw) ?? .uvToolRun
        self.astrBotCustomCommand = store.string(forKey: Key.astrBotCustomCommand) ?? ""
        self.astrBotExecutablePath = store.string(forKey: Key.astrBotExecutablePath) ?? ""
        self.astrBotScriptPath = store.string(forKey: Key.astrBotScriptPath) ?? ""
        let port = store.integer(forKey: Key.astrBotWebPort)
        self.astrBotWebPort = port > 0 ? port : 6185

        // 容器
        self.napcatContainer = store.string(forKey: Key.napcatContainer) ?? ""
        self.shipyardContainer = store.string(forKey: Key.shipyardContainer) ?? ""
        self.manualComposePaths = store.stringArray(forKey: Key.manualComposePaths) ?? []
        let selectedRaw = store.string(forKey: Key.selectedService) ?? ServiceType.napcat.rawValue
        self.selectedService = ServiceType(rawValue: selectedRaw) ?? .napcat

        // 服务顺序（Finder 风格：按 displayName 字母升序）
        let storedOrder = (store.array(forKey: Key.serviceOrder) as? [String]) ?? []
        let allTypes = ServiceType.allCases
        let defaultOrder = allTypes.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if storedOrder.isEmpty {
            // 首次启动：Finder 风格字母排序
            self.serviceOrder = defaultOrder
        } else {
            // 已存储：使用用户顺序，但追加新出现的服务（按字母位置插入）
            let storedTypes = storedOrder.compactMap { ServiceType(rawValue: $0) }
            let missing = allTypes.filter { !storedTypes.contains($0) }
            var finalOrder = storedTypes
            for type in missing {
                if let insertIndex = finalOrder.firstIndex(where: { type.displayName.localizedCaseInsensitiveCompare($0.displayName) == .orderedAscending }) {
                    finalOrder.insert(type, at: insertIndex)
                } else {
                    finalOrder.append(type)
                }
            }
            self.serviceOrder = finalOrder
        }

        // Paths
        let homeDir = NSHomeDirectory()
        self.astrbotLogPath = store.string(forKey: Key.astrbotLogPath) ?? "\(homeDir)/data/logs/astrbot.log"
        self.dataDirectory = store.string(forKey: Key.dataDirectory) ?? "\(homeDir)/data"

        // Behavior
        let interval = store.integer(forKey: Key.pollingInterval)
        self.pollingInterval = interval > 0 ? interval : 5
        self.autoStartOnBoot = store.bool(forKey: Key.autoStartOnBoot)
        self.startMinimized = store.bool(forKey: Key.startMinimized)
        self.autoStartAllServices = store.bool(forKey: Key.autoStartAllServices)

        let themeRaw = store.string(forKey: Key.themeMode) ?? ThemeMode.system.rawValue
        self.themeMode = ThemeMode(rawValue: themeRaw) ?? .system
        self.enableNotifications = store.object(forKey: Key.enableNotifications) as? Bool ?? true
    }

    /// 展开路径中的 ~
    func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

/// 主题模式
enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
