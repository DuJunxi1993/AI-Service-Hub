import SwiftUI

/// 主题色 / 间距 / 动效常量（macOS 26 Liquid Glass 调色）
enum Theme {
    // MARK: - 强调色（参考 macOS 26 原生应用）
    static let accent = Color.accentColor  // 系统强调色

    // 状态操作色
    static let startColor = Color.green
    static let stopColor = Color.red
    static let restartColor = Color.orange
    static let openColor = Color.blue

    // 文字色阶
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText: Color = Color(white: 0.5)

    // MARK: - 间距 & 圆角
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 12
    static let smallRadius: CGFloat = 8

    static let cardPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 14

    // MARK: - 动效
    static let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let quickAnimation = Animation.easeInOut(duration: 0.2)
    static let morphAnimation = Animation.spring(response: 0.45, dampingFraction: 0.75)
}
