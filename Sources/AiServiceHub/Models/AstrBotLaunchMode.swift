import Foundation

/// AstrBot 启动模式
enum AstrBotLaunchMode: String, Codable, CaseIterable, Identifiable {
    case uvToolRun         // uv tool run astrbot
    case customCommand     // 自定义命令
    case executablePath    // 可执行文件路径
    case shellScript       // shell 脚本

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uvToolRun: return "uv tool run (推荐)"
        case .customCommand: return "自定义命令"
        case .executablePath: return "可执行文件"
        case .shellScript: return "Shell 脚本"
        }
    }

    var description: String {
        switch self {
        case .uvToolRun: return "uv 全局工具方式启动 AstrBot"
        case .customCommand: return "执行用户输入的完整命令"
        case .executablePath: return "直接执行指定路径的二进制"
        case .shellScript: return "通过 shell 脚本启动"
        }
    }

    var iconName: String {
        switch self {
        case .uvToolRun: return "wand.and.stars"
        case .customCommand: return "terminal"
        case .executablePath: return "app.badge"
        case .shellScript: return "scroll"
        }
    }
}
