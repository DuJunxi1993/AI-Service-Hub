import Foundation

/// 应用内部使用的通知名
extension Notification.Name {
    /// 从菜单栏（或全局快捷键）触发「显示主窗口」
    static let showMainWindow = Notification.Name("ShowMainWindow")
}
