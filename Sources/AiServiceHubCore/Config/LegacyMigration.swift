import Foundation

/// 从旧版 UserDefaults 迁移配置
///
/// 旧版把配置存在 `com.djx.astrbotlauncher` 这个 bundle id 的域里。
/// 本程序改名为 AI Service Hub 后 bundle id 变成 `com.djx.aiservicehub`，
/// `UserDefaults.standard` 指向了一个新的空域，因此必须**显式读旧域**才能
/// 把用户已有的配置带过来。
public enum LegacyMigration {
    /// 旧版 bundle id
    public static let legacyBundleID = "com.djx.astrbotlauncher"

    /// 旧版的 UserDefaults 域
    public static func legacyDefaults() -> UserDefaults {
        UserDefaults(suiteName: legacyBundleID) ?? .standard
    }

    // 旧版 key
    private enum Key {
        static let astrBotLaunchMode = "astrBotLaunchMode"
        static let astrBotCustomCommand = "astrBotCustomCommand"
        static let astrBotExecutablePath = "astrBotExecutablePath"
        static let astrBotScriptPath = "astrBotScriptPath"
        static let astrBotWebPort = "astrBotWebPort"
        static let napcatContainer = "napcatContainer"
        static let shipyardContainer = "shipyardContainer"
        static let manualComposePaths = "manualComposePaths"
        static let astrbotLogPath = "astrbotLogPath"
        static let dataDirectory = "dataDirectory"
        static let pollingInterval = "pollingInterval"
        static let autoStartOnBoot = "autoStartOnBoot"
        static let startMinimized = "startMinimized"
        static let autoStartAllServices = "autoStartAllServices"
        static let themeMode = "themeMode"
        static let enableNotifications = "enableNotifications"
        static let selectedService = "selectedService"
        static let serviceOrder = "serviceOrder"
    }

    /// 是否存在可迁移的旧数据
    public static func hasLegacyData(defaults: UserDefaults? = nil) -> Bool {
        let defaults = defaults ?? legacyDefaults()
        return defaults.object(forKey: Key.astrBotLaunchMode) != nil
            || defaults.object(forKey: Key.napcatContainer) != nil
            || defaults.object(forKey: Key.dataDirectory) != nil
    }

    /// 执行迁移，产出新的配置
    public static func migrate(defaults: UserDefaults? = nil) -> AppConfig {
        let defaults = defaults ?? legacyDefaults()

        var services: [ServiceDescriptor] = []
        var legacyNameToID: [String: UUID] = [:]

        // 1. AstrBot
        let astrBot = makeAstrBotDescriptor(defaults: defaults)
        services.append(astrBot)
        legacyNameToID["astrbot"] = astrBot.id

        // 2. 旧版为 NapCat 存过容器名 —— 转成「委托容器」服务
        //    （Shipyard 已从内置预设中移除，不再迁移）
        for (legacyKey, legacyName, displayName, accent) in [
            (Key.napcatContainer, "napcat", "NapCat", RGBAColor.cyan)
        ] {
            let containerName = (defaults.string(forKey: legacyKey) ?? "").trimmingCharacters(in: .whitespaces)
            guard !containerName.isEmpty else { continue }
            let descriptor = ServiceDescriptor(
                name: displayName,
                lifecycle: .managed,
                enabled: true,
                autoStart: false,
                appearance: Appearance(iconSymbol: "shippingbox.fill", accent: accent),
                managed: .container(ContainerSpec(
                    containerName: containerName,
                    composePath: nil,
                    stopOnAppQuit: true
                )),
                probes: [],
                logSources: [
                    .dockerLogs(
                        id: "\(legacyName)-logs",
                        label: "容器日志",
                        containerName: containerName,
                        webUIKind: legacyName == "napcat" ? .napCat : nil
                    )
                ],
                openURL: nil,
                note: "由旧版配置迁移而来"
            )
            services.append(descriptor)
            legacyNameToID[legacyName] = descriptor.id
        }

        // 3. 偏好
        let interval = defaults.integer(forKey: Key.pollingInterval)
        let themeRaw = defaults.string(forKey: Key.themeMode) ?? ThemeMode.system.rawValue

        var preferences = Preferences(
            themeMode: ThemeMode(rawValue: themeRaw) ?? .system,
            pollingIntervalSeconds: interval > 0 ? interval : 5,
            enableNotifications: defaults.object(forKey: Key.enableNotifications) as? Bool ?? true,
            startMinimized: defaults.bool(forKey: Key.startMinimized),
            loginItemEnabled: defaults.bool(forKey: Key.autoStartOnBoot),
            autoStartAllServices: defaults.object(forKey: Key.autoStartAllServices) as? Bool ?? true
        )

        // 4. 侧边栏顺序与选中项
        let storedOrder = (defaults.array(forKey: Key.serviceOrder) as? [String]) ?? []
        if !storedOrder.isEmpty {
            let mapped = storedOrder.compactMap { legacyNameToID[$0] }
            let remaining = services.map(\.id).filter { !mapped.contains($0) }
            preferences.sidebarOrder = mapped + remaining
        } else {
            preferences.sidebarOrder = services
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(\.id)
        }

        if let selectedRaw = defaults.string(forKey: Key.selectedService),
           let selectedID = legacyNameToID[selectedRaw] {
            preferences.selectedServiceID = selectedID
        }

        return AppConfig(
            schemaVersion: AppConfig.currentSchemaVersion,
            preferences: preferences,
            services: services,
            ownedProcesses: []
        )
    }

    // MARK: - 私有

    private static func makeAstrBotDescriptor(defaults: UserDefaults) -> ServiceDescriptor {
        let home = NSHomeDirectory()
        let logPath = defaults.string(forKey: Key.astrbotLogPath) ?? "\(home)/data/logs/astrbot.log"
        let dataDirectory = defaults.string(forKey: Key.dataDirectory) ?? "\(home)/data"
        let port = defaults.integer(forKey: Key.astrBotWebPort)
        let webPort = port > 0 ? port : 6185

        var descriptor = AstrBotPreset.makeDescriptor(
            webPort: webPort,
            logPath: logPath,
            dataDirectory: dataDirectory
        )
        descriptor.presetIdentifier = AstrBotPreset.identifier

        // 启动模式
        let mode = defaults.string(forKey: Key.astrBotLaunchMode) ?? "uvToolRun"
        switch mode {
        case "customCommand":
            let command = (defaults.string(forKey: Key.astrBotCustomCommand) ?? "")
                .trimmingCharacters(in: .whitespaces)
            if !command.isEmpty {
                let parsed = ShellArgumentParser.parse(command)
                let needsShell = ShellArgumentParser.requiresShell(command) != nil
                descriptor.managed = .process(ProcessSpec(
                    executable: parsed.executable,
                    arguments: parsed.arguments,
                    workingDirectory: PathExpander.parentDirectory(of: dataDirectory),
                    environment: [:],
                    shellMode: needsShell,
                    ownership: .daemon,
                    processMatch: AstrBotPreset.processMatchPatterns()
                ))
            }
        case "executablePath":
            let path = (defaults.string(forKey: Key.astrBotExecutablePath) ?? "")
                .trimmingCharacters(in: .whitespaces)
            if !path.isEmpty {
                descriptor.managed = .process(ProcessSpec(
                    executable: PathExpander.expand(path),
                    arguments: [],
                    workingDirectory: PathExpander.parentDirectory(of: dataDirectory),
                    environment: [:],
                    shellMode: false,
                    ownership: .daemon,
                    processMatch: AstrBotPreset.processMatchPatterns()
                ))
            }
        case "shellScript":
            let script = (defaults.string(forKey: Key.astrBotScriptPath) ?? "")
                .trimmingCharacters(in: .whitespaces)
            if !script.isEmpty {
                descriptor.managed = .process(ProcessSpec(
                    executable: "/bin/bash",
                    arguments: [PathExpander.expand(script)],
                    workingDirectory: PathExpander.parentDirectory(of: dataDirectory),
                    environment: [:],
                    shellMode: false,
                    ownership: .daemon,
                    processMatch: AstrBotPreset.processMatchPatterns()
                ))
            }
        default:
            break  // uvToolRun 使用预设的默认值
        }

        return descriptor
    }
}
