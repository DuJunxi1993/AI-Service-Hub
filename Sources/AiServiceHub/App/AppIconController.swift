import AppKit
import SwiftUI
import Combine
import AiServiceHubCore

/// Dock 图标控制器 —— 让**运行中**的 Dock 图标跟随系统明暗
///
/// ## 为什么需要它
///
/// macOS 的 bundle 图标（Finder 里看到的、app 未运行时 Dock 里的那个）
/// **不会**随系统外观变化。给 asset catalog 里的 appiconset 标
/// `appearances: luminosity/dark` 是**空操作** —— actool 会静默丢弃深色 rendition，
/// 编译出的 `Assets.car` 里只剩 "Any"。
/// （iOS 18 才有这个能力，macOS 没有。）
///
/// macOS 上唯一能跟随外观变化的是**运行中**的 Dock 图标，
/// 也就是 `NSApp.applicationIconImage` —— 它在运行时可设。
///
/// 所以做法是：
/// - bundle 里放两套 `.icns`（浅色 / 深色）
/// - bundle 图标用浅色那套（Finder / 未运行时显示，macOS 在暗色下会自行做暗化）
/// - 运行中按**系统外观**切换 `applicationIconImage`
///
/// ## 注意：跟随的是系统，不是应用内主题
///
/// 应用内的主题设置（跟随系统 / 浅色 / 深色）只影响界面配色。
/// 图标跟随**系统**外观 —— 白天浅色、夜间深色。
/// 否则应用内选了「浅色」时，夜间 Dock 里仍是浅色图标，与环境不一致。
@MainActor
final class AppIconController {
    static let shared = AppIconController()

    private var appearanceObservation: NSKeyValueObservation?
    private var pollTimer: Timer?
    private var lastSystemIsDark = false

    private lazy var lightIcon = Self.loadIcon(named: "ai_service_hub")
    private lazy var darkIcon = Self.loadIcon(named: "ai_service_hub_dark")

    private init() {}

    /// 启动图标跟随
    func start() {
        // 系统切换明暗时 KVO 会触发 —— 立即换图标
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }

        // 兜底轮询：应用若强制了窗口外观，KVO 不一定反映系统变化
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSystemAppearance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        lastSystemIsDark = SystemAppearance.isDark()
        apply()
    }

    /// 检查系统外观是否变化
    private func pollSystemAppearance() {
        let isDark = SystemAppearance.isDark()
        guard isDark != lastSystemIsDark else { return }
        lastSystemIsDark = isDark
        apply()
    }

    /// 应用图标
    private func apply() {
        let useDark = SystemAppearance.isDark()
        let icon = useDark ? darkIcon : lightIcon
        guard let icon else {
            NSApp.applicationIconImage = nil  // 回落到 bundle 图标
            return
        }
        if NSApp.applicationIconImage != icon {
            NSApp.applicationIconImage = icon
        }
        AppLog.info("Dock 图标：\(useDark ? "深色" : "浅色")（跟随系统外观）")
    }

    /// 从 bundle 读取 .icns
    private static func loadIcon(named name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }
}
