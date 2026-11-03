import Foundation
import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement

/// 依赖真实 app bundle 的系统能力在「直接跑二进制」的开发模式下不可用：
/// UNUserNotificationCenter / SMAppService 都需要 bundleProxyForCurrentProcess，
/// 否则会抛 NSInternalInconsistencyException。开发模式（run.sh）下统一跳过。
enum BundleAvailability {
    /// 是否运行在正式的 .app bundle 内
    static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }
}

/// 登录项管理
@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()

    /// 检查当前是否注册为登录项
    var isEnabled: Bool {
        guard BundleAvailability.isBundled else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// 注册 / 取消注册
    func setEnabled(_ enabled: Bool) {
        guard BundleAvailability.isBundled else {
            AppLog.warn("未运行在 app bundle 内，跳过登录项注册")
            return
        }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            AppLog.error("LoginItem error: \(error.localizedDescription)")
        }
    }
}

/// 系统通知
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    func requestAuthorization() {
        guard BundleAvailability.isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(title: String, body: String) {
        guard BundleAvailability.isBundled else { return }
        guard AppSettings.shared.enableNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.warn("Notification failed: \(error.localizedDescription)")
            }
        }
    }
}
