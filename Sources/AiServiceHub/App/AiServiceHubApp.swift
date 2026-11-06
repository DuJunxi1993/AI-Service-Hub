import SwiftUI
import AppKit
import AiServiceHubCore

@main
struct AiServiceHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appModel = AppModel.shared
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
                .environmentObject(appModel)
                .environmentObject(settings)
                .frame(minWidth: 820, idealWidth: 960, minHeight: 500, idealHeight: 620)
                .preferredColorScheme(settings.themeMode.colorScheme)
        }
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
                ForEach(settings.orderedServices) { descriptor in
                    Button("启动 \(descriptor.name)") {
                        Task { await appModel.start(descriptor.id) }
                    }
                    .keyboardShortcut(shortcutKey(for: descriptor), modifiers: [.command])
                    .disabled(descriptor.lifecycle != .managed)

                    Button("停止 \(descriptor.name)") {
                        Task { await appModel.stop(descriptor.id) }
                    }
                    .keyboardShortcut(shortcutKey(for: descriptor), modifiers: [.command, .shift])
                    .disabled(descriptor.lifecycle != .managed)
                }
                Divider()
                Button("全部启动") {
                    Task { await appModel.startAll() }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("全部停止") {
                    Task { await appModel.stopAll() }
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
    }

    /// 每个服务的快捷键（按侧边栏顺序分配数字键）
    private func shortcutKey(for descriptor: ServiceDescriptor) -> KeyEquivalent {
        let index = settings.orderedServices.firstIndex { $0.id == descriptor.id } ?? 0
        let digits: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        return KeyEquivalent(digits[index % digits.count])
    }
}

extension ThemeMode {
    /// 对应的 SwiftUI 配色方案（nil 表示跟随系统）
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// AppDelegate - 处理启动时最小化、菜单栏、退出清理
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didCleanUp = false
    /// 窗口关闭通知的观察者
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 激活应用（必须在所有窗口设置之前）
        NSApp.setActivationPolicy(.regular)

        // 主窗口激活
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title.contains("AI Service Hub") {
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
            MenuBarController.shared.setup(appModel: AppModel.shared)
        }

        // 请求通知权限
        NotificationManager.shared.requestAuthorization()

        // Dock 图标跟随系统明暗（macOS 只有运行中的图标能变）
        AppIconController.shared.start()



        // 主窗口关闭 → 让出前台（见 resignFrontmostIfNoWindowVisible）
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  window.title.contains("AI Service Hub") else { return }
            self?.resignFrontmostIfNoWindowVisible()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 窗口可能已经被**关闭**（close），而 orderFront 对已关闭的 NSWindow 无效，
        // 会得到一个「唤不回来」的空窗口。统一走 openWindow ——
        // 它由 SwiftUI 场景负责，能正确重建/重显。
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
    }

    /// 主窗口关闭后：app 继续在后台跑，但**要让出前台**
    ///
    /// macOS 的惯例（Finder 为例）：关掉全部窗口后 app 仍在运行，
    /// 但会卸下前台身份 —— 否则台前调度会为它留一个空舞台，
    /// 菜单栏也还挂着这个 app 的名字。
    ///
    /// 这里用 `NSApp.hide(nil)` 而不是单纯 orderOut：
    /// 只有 hide 才会让 app 退出前台状态。
    private func resignFrontmostIfNoWindowVisible() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 只认「有实际尺寸的窗口」—— SwiftUI 场景内部还有几个 34×30 的
            // 模板窗口，它们 visible=true 但不是用户看到的窗口。
            let hasRealWindow = NSApp.windows.contains {
                $0.isVisible && $0.frame.width > 200 && $0.frame.height > 200
            }
            guard !hasRealWindow else { return }
            NSApp.hide(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // 主窗口关闭时不退出（菜单栏仍可用）
    }

    deinit {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }

    /// 退出前先做清理（需要 await，因此推迟真正退出）
    ///
    /// - daemon 化的进程不在此终止；
    /// - 容器按各自配置决定是否停止。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didCleanUp else { return .terminateNow }
        didCleanUp = true
        Task { @MainActor in
            await AppModel.shared.cleanupOnExit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
