import Foundation

/// 与界面无关的强调色（Core 不依赖 SwiftUI，由 App 层映射成 Color）
public struct RGBAColor: Codable, Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let orange = RGBAColor(red: 0.95, green: 0.55, blue: 0.20)
    public static let cyan = RGBAColor(red: 0.25, green: 0.72, blue: 0.85)
    public static let purple = RGBAColor(red: 0.55, green: 0.45, blue: 0.95)
    public static let green = RGBAColor(red: 0.30, green: 0.70, blue: 0.42)
    public static let gray = RGBAColor(red: 0.55, green: 0.55, blue: 0.58)
}

/// 服务的展示元数据
public struct Appearance: Codable, Sendable, Hashable {
    /// SF Symbol 名称
    public var iconSymbol: String
    /// 强调色
    public var accent: RGBAColor

    public init(iconSymbol: String, accent: RGBAColor) {
        self.iconSymbol = iconSymbol
        self.accent = accent
    }
}
