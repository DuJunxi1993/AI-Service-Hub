import SwiftUI
import AppKit

@main
struct AiServiceHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var settings = AppSettings.shared
    @State private var showSettings: Bool = false

    init() {
        // 清理可能由 v1.0.0/v1.0.1 留下的不兼容 toolbar customization state
        // macOS 26.5.1 的 .toolbar(id:) 在加载旧 customization state 时会崩溃
        Self.cleanupLegacyToolbarState()
    }

    /// 清理旧 toolbar customization 的 UserDefaults keys
    private static func cleanupLegacyToolbarState() {
        let defaults = UserDefaults.standard
        let legacyKeys = [
            "NSNavToolbarCustomization-main.toolbar",
            "NSNavToolbarCustomization-main.toolbar.v2",
            "NSToolbar Identifier Main.toolbar",
            "NSToolbar Identifier Main.toolbar.v2",
            // 通配所有可能残留的 toolbar customization keys
            "NSNavToolbarCustomization-main"
        ]
        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }
    }

    var body: some Scene {
        // 用 Window(id:) 而非 WindowGroup —— WindowGroup 的窗口在关闭后会被销毁，
        // 导致 NSApp.windows 找不到窗口，菜单栏点击无效。Window(id:) 是持久单窗口，
        // 关闭后仍可通过 openWindow(id:) 重新显示。
        Window("AI Service Hub", id: "main") {
            MainWindowView(showSettings: $showSettings)
                .environmentObject(appState)
                .environmentObject(settings)
                .frame(minWidth: 760, idealWidth: 900, minHeight: 500, idealHeight: 620)
                .preferredColorScheme(settings.themeMode.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("设置...") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            // 不再添加 ToolbarCommands() —— macOS 26.5.1 的 .toolbar(id:) 会崩溃
            // 所有 toolbar items 在 .toolbar { } 中固定显示
            CommandMenu("服务") {
                ForEach(ServiceType.allCases) { type in
                    Button("启动 \(type.displayName)") {
                        Task { await appState.startService(type) }
                    }
                    .keyboardShortcut(shortcutKey(for: type), modifiers: [.command])

                    Button("停止 \(type.displayName)") {
                        Task { await appState.stopService(type) }
                    }
                    .keyboardShortcut(shortcutKey(for: type), modifiers: [.command, .shift])
                }
                Divider()
                Button("全部启动") {
                    Task { await appState.startAll() }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("全部停止") {
                    Task { await appState.stopAll() }
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
    }

    private func shortcutKey(for type: ServiceType) -> KeyEquivalent {
        switch type {
        case .napcat: return "1"
        case .shipyard: return "2"
        case .astrbot: return "3"
        }
    }
}

/// AppDelegate - 处理启动时最小化、菜单栏
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 激活应用（必须在所有窗口设置之前）
        NSApp.setActivationPolicy(.regular)

        // 主窗口激活
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title.contains("AstrBot") {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }

        // 启动时最小化到 Dock
        if AppSettings.shared.startMinimized {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.windows.first?.miniaturize(nil)
            }
        }

        // 设置菜单栏（延迟到 UI 准备好后）
        DispatchQueue.main.async {
            MenuBarController.shared.setup(appState: AppState.shared)
        }

        // 请求通知权限
        NotificationManager.shared.requestAuthorization()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 应用变为活跃时激活主窗口
        for window in NSApp.windows where window.title.contains("AstrBot") {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // 主窗口关闭时不退出（菜单栏仍可用）
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.cleanupOnExit()
    }
}
