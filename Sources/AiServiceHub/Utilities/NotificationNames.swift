import Foundation

/// WebUI URL 检测通知
extension Notification.Name {
    /// 日志中检测到 WebUI URL
    /// userInfo:
    ///   - "source": LogSource
    ///   - "url": URL
    static let webUIDetected = Notification.Name("WebUIDetected")

    /// 从菜单栏（或全局快捷键）触发"显示主窗口"
    static let showMainWindow = Notification.Name("ShowMainWindow")
}
