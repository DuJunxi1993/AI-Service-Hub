import AppKit
import SwiftUI
import AiServiceHubCore

/// 菜单栏常驻控制器
@MainActor
final class MenuBarController: ObservableObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var appModel: AppModel?
    private var settings: AppSettings?

    private init() {}

    /// 菜单栏图标
    ///
    /// 用品牌图形（`menubar-icon.png`）而不是 SF Symbol。
    /// 它是**模板图**（template image）：macOS 只取 alpha 通道，
    /// 按菜单栏当前的明暗状态着色，所以一份资源就能适配两种外观。
    private static func menuBarIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        // 兜底：资源缺失时用系统符号
        return NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "AI Service Hub")
    }

    func setup(appModel: AppModel, settings: AppSettings = .shared) {
        self.appModel = appModel
        self.settings = settings

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.image = Self.menuBarIcon()
                button.image?.isTemplate = true
                button.action = #selector(handleClick(_:))
                button.target = self
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
        }

        updateMenu()

        // 定期刷新菜单内容
        Task { @MainActor in
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.updateMenu()
            }
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            toggleMainWindow()
        }
    }

    private func toggleMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.title.contains("AI Service Hub") }) {
            if window.isVisible && window.isKeyWindow {
                window.orderOut(nil)
                return
            }
        }
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
    }

    func updateMenu() {
        guard let appModel, let settings else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "AI Service Hub", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statItem = NSMenuItem(
            title: "\(appModel.runningCount) / \(appModel.totalCount) 运行中",
            action: nil,
            keyEquivalent: ""
        )
        statItem.isEnabled = false
        menu.addItem(statItem)

        menu.addItem(.separator())

        // 各服务快捷操作
        for descriptor in settings.orderedServices {
            let snapshot = appModel.snapshots[descriptor.id]
            let serviceMenu = NSMenu()

            var titleText = "\(descriptor.name) — \(snapshot?.status.displayName ?? "未知")"
            if descriptor.lifecycle == .observed {
                titleText += "（只读）"
            } else if snapshot?.startedByUs == false, snapshot?.status == .running {
                titleText += "（外部）"
            }
            let titleItem = NSMenuItem(title: titleText, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            serviceMenu.addItem(titleItem)
            serviceMenu.addItem(.separator())

            let isManaged = descriptor.lifecycle == .managed

            let startItem = NSMenuItem(title: "启动", action: #selector(menuStartService(_:)), keyEquivalent: "")
            startItem.target = self
            startItem.representedObject = descriptor.id
            startItem.isEnabled = isManaged && (snapshot?.status.canStart ?? true)
            serviceMenu.addItem(startItem)

            let stopItem = NSMenuItem(title: "停止", action: #selector(menuStopService(_:)), keyEquivalent: "")
            stopItem.target = self
            stopItem.representedObject = descriptor.id
            stopItem.isEnabled = isManaged && (snapshot?.status.canStop ?? false)
            serviceMenu.addItem(stopItem)

            serviceMenu.addItem(.separator())

            let openItem = NSMenuItem(title: "打开 WebUI", action: #selector(menuOpenWebUI(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = descriptor.id
            openItem.isEnabled = snapshot?.webURL != nil
            serviceMenu.addItem(openItem)

            let topItem = NSMenuItem(title: descriptor.name, action: nil, keyEquivalent: "")
            topItem.submenu = serviceMenu
            menu.addItem(topItem)
        }

        menu.addItem(.separator())

        let startAllItem = NSMenuItem(title: "全部启动", action: #selector(menuStartAll), keyEquivalent: "")
        startAllItem.target = self
        menu.addItem(startAllItem)

        let stopAllItem = NSMenuItem(title: "全部停止", action: #selector(menuStopAll), keyEquivalent: "")
        stopAllItem.target = self
        menu.addItem(stopAllItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(menuShowWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        if let item = statusItem { item.menu = nil }
    }

    @objc private func menuStartService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let appModel else { return }
        Task { await appModel.start(id) }
    }

    @objc private func menuStopService(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let appModel else { return }
        Task { await appModel.stop(id) }
    }

    @objc private func menuOpenWebUI(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let appModel else { return }
        appModel.openWebUI(id)
    }

    @objc private func menuStartAll() {
        guard let appModel else { return }
        Task { await appModel.startAll() }
    }

    @objc private func menuStopAll() {
        guard let appModel else { return }
        Task { await appModel.stopAll() }
    }

    @objc private func menuShowWindow() {
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
