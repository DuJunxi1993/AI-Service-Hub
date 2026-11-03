import AppKit
import SwiftUI

/// 菜单栏常驻控制器
@MainActor
final class MenuBarController: ObservableObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var appState: AppState?

    private init() {}

    func setup(appState: AppState) {
        self.appState = appState

        // 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "AI Service Hub")
            button.image?.isTemplate = true
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 初始化菜单
        updateMenu()

        // 监听 AppState 变化，刷新菜单
        // 每 5 秒刷新一次（用 NotificationCenter 而非 Timer，避免额外开销）
        Task { @MainActor in
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.updateMenu()
            }
        }
    }

    /// 便捷访问 AstrBotController
    private var astrBotController: AstrBotController {
        AppState.shared.strBotController
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // 右键显示菜单
            menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            // 左键显示/隐藏主窗口
            toggleMainWindow()
        }
    }

    private func toggleMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // 找到持久窗口（Window(id:) 创建的窗口关闭后仍存在）
        if let window = NSApp.windows.first(where: { $0.title.contains("AstrBot") }) {
            if window.isVisible && window.isKeyWindow {
                window.orderOut(nil)
                return
            }
            // 让 SwiftUI 通过 openWindow 重新显示（处理所有边缘情况）
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        } else {
            // 兜底：post 通知让 SwiftUI 通过 openWindow 重新创建窗口
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }
    }

    func updateMenu() {
        guard let appState else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 标题
        let titleItem = NSMenuItem(title: "AI Service Hub", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        // 状态统计
        let runningCount = appState.runningCount
        let totalCount = appState.totalCount
        let statItem = NSMenuItem(title: "\(runningCount) / \(totalCount) 运行中", action: nil, keyEquivalent: "")
        statItem.isEnabled = false
        menu.addItem(statItem)

        menu.addItem(.separator())

        // 各服务快捷操作
        for type in ServiceType.allCases {
            let svc = appState.services[type] ?? Service(type: type)
            let serviceMenu = NSMenu()

            // 标题带 daemon 标记
            var titleText = "\(type.displayName) — \(svc.status.displayName)"
            if type == .astrbot, svc.status == .running, !astrBotController.startedByUs {
                titleText += " (外部)"
            }
            let titleItem = NSMenuItem(title: titleText, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            serviceMenu.addItem(titleItem)
            serviceMenu.addItem(.separator())

            let startItem = NSMenuItem(
                title: "启动",
                action: #selector(menuStartService(_:)),
                keyEquivalent: ""
            )
            startItem.target = self
            startItem.representedObject = type
            startItem.isEnabled = svc.status.canStart
            serviceMenu.addItem(startItem)

            let stopItem = NSMenuItem(
                title: "停止",
                action: #selector(menuStopService(_:)),
                keyEquivalent: ""
            )
            stopItem.target = self
            stopItem.representedObject = type
            stopItem.isEnabled = svc.status.canStop
            serviceMenu.addItem(stopItem)

            serviceMenu.addItem(.separator())

            let openItem = NSMenuItem(
                title: "打开 WebUI",
                action: #selector(menuOpenWebUI(_:)),
                keyEquivalent: ""
            )
            openItem.target = self
            openItem.representedObject = type
            openItem.isEnabled = svc.webPort != nil
            serviceMenu.addItem(openItem)

            let topItem = NSMenuItem(title: type.displayName, action: nil, keyEquivalent: "")
            topItem.submenu = serviceMenu
            menu.addItem(topItem)
        }

        menu.addItem(.separator())

        // 全部启停
        let startAllItem = NSMenuItem(title: "全部启动", action: #selector(menuStartAll), keyEquivalent: "")
        startAllItem.target = self
        menu.addItem(startAllItem)

        let stopAllItem = NSMenuItem(title: "全部停止", action: #selector(menuStopAll), keyEquivalent: "")
        stopAllItem.target = self
        menu.addItem(stopAllItem)

        menu.addItem(.separator())

        // 显示窗口
        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(menuShowWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        // 退出
        let quitItem = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        if let item = statusItem { item.menu = nil }  // 左键时无菜单（由 click handler 控制）
    }

    @objc private func menuStartService(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? ServiceType, let appState else { return }
        Task { await appState.startService(type) }
    }

    @objc private func menuStopService(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? ServiceType, let appState else { return }
        Task { await appState.stopService(type) }
    }

    @objc private func menuOpenWebUI(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? ServiceType, let appState else { return }
        appState.openWebUI(type)
    }

    @objc private func menuStartAll() {
        guard let appState else { return }
        Task { await appState.startAll() }
    }

    @objc private func menuStopAll() {
        guard let appState else { return }
        Task { await appState.stopAll() }
    }

    @objc private func menuShowWindow() {
        // 通过通知统一路径（与左键点击处理一致）
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    /// 触发菜单显示
    func showMenu() {
        if let button = statusItem?.button, let menu = self.menu {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }
}
