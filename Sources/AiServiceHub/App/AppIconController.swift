import AppKit
import SwiftUI
import Combine
import AiServiceHubCore

/// Dock 图标控制器 —— 让**运行中**的 Dock 图标跟随明暗主题
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
/// - bundle 图标用浅色那套（Finder / 未运行时显示）
/// - 运行中按有效外观切换 `applicationIconImage`
@MainActor
final class AppIconController {
    static let shared = AppIconController()

    private var appearanceObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    private lazy var lightIcon = Self.loadIcon(named: "ai_service_hub")
    private lazy var darkIcon = Self.loadIcon(named: "ai_service_hub_dark")

    private init() {}

    /// 启动图标跟随
    func start(settings: AppSettings) {
        // 有效外观变化：系统切换明暗，或 app 自身设置改变了 appearance
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }

        // 主题设置变化（跟随系统 / 浅色 / 深色）
        settings.$themeMode
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            .store(in: &cancellables)

        apply()
    }

    /// 按当前外观应用图标
    private func apply() {
        let useDark = shouldUseDarkIcon()
        let icon = useDark ? darkIcon : lightIcon
        guard let icon else {
            NSApp.applicationIconImage = nil  // 回落到 bundle 图标
            return
        }
        if NSApp.applicationIconImage != icon {
            NSApp.applicationIconImage = icon
        }
        AppLog.info("Dock 图标：\(useDark ? "深色" : "浅色")（主题=\(AppSettings.shared.themeMode.rawValue)）")
    }

    /// 该用深色图标吗
    ///
    /// 优先看 app 的主题设置（跟随系统 / 浅色 / 深色）——
    /// 它比系统外观更贴合用户在设置里选的模式。
    private func shouldUseDarkIcon() -> Bool {
        switch AppSettings.shared.themeMode {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    /// 从 bundle 读取 .icns
    private static func loadIcon(named name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }
}
