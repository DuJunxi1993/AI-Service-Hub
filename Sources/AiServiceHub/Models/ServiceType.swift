import SwiftUI

/// 服务类型
enum ServiceType: String, Codable, CaseIterable, Identifiable, Hashable {
    case astrbot
    case napcat
    case shipyard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .astrbot: return "AstrBot"
        case .napcat: return "NapCat"
        case .shipyard: return "Shipyard"
        }
    }

    /// SF Symbol 图标
    var iconName: String {
        switch self {
        case .astrbot: return "gearshape.2.fill"
        case .napcat: return "bubble.left.and.bubble.right.fill"
        case .shipyard: return "cloud.fill"
        }
    }

    /// 主题色（用于图标和强调）
    var accentColor: Color {
        switch self {
        case .astrbot: return Color(red: 0.95, green: 0.55, blue: 0.20) // 橙色
        case .napcat: return Color(red: 0.25, green: 0.72, blue: 0.85) // 青蓝
        case .shipyard: return Color(red: 0.55, green: 0.45, blue: 0.95) // 紫
        }
    }

    /// 副标题
    var subtitle: String {
        switch self {
        case .astrbot: return "AI 机器人框架"
        case .napcat: return "QQ 协议端"
        case .shipyard: return "Agent 调度平台"
        }
    }

    /// 根据镜像名推断服务类型
    static func from(image: String) -> ServiceType? {
        let lower = image.lowercased()
        if lower.contains("napcat") { return .napcat }
        if lower.contains("shipyard") { return .shipyard }
        if lower.contains("astrbot") { return .astrbot }
        return nil
    }

    /// 根据容器名推断服务类型（兜底）
    static func from(containerName: String) -> ServiceType? {
        let lower = containerName.lowercased()
        if lower.contains("napcat") { return .napcat }
        if lower.contains("shipyard") { return .shipyard }
        if lower.contains("astrbot") { return .astrbot }
        return nil
    }
}
