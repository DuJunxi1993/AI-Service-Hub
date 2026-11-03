import Foundation

/// 从日志行中检测 WebUI URL
/// 根据服务类型使用不同的模式：
/// - AstrBot: "Starting WebUI at <URL>" 或 "Local: <URL>"（显式排除 "Network:"）
/// - NapCat: "WebUi User Panel Url: <URL>"（只取 IPv4 127.0.0.1，跳过 IPv6 [::]）
/// - Shipyard: 日志中没有 WebUI 启动信息（API 8156 vs Dashboard 8157），返回 nil（用 compose 解析）
enum WebUIURLDetector {
    /// 统一入口
    static func extract(from line: String, for type: ServiceType) -> URL? {
        switch type {
        case .astrbot:
            return extractAstrBotURL(from: line)
        case .napcat:
            return extractNapCatURL(from: line)
        case .shipyard:
            return nil
        }
    }

    // MARK: - AstrBot

    private static func extractAstrBotURL(from line: String) -> URL? {
        if let range = line.range(of: "Starting WebUI at ", options: .caseInsensitive) {
            if let url = firstURL(in: String(line[range.upperBound...])) {
                return url
            }
        }
        if line.contains("Local:"), !line.contains("Network:") {
            if let url = firstURL(in: line) {
                return url
            }
        }
        return nil
    }

    // MARK: - NapCat

    private static func extractNapCatURL(from line: String) -> URL? {
        guard let range = line.range(of: "WebUi User Panel Url: ", options: .caseInsensitive) else {
            return nil
        }
        let payload = String(line[range.upperBound...])
        guard firstIPv4URL(in: payload) != nil else {
            return nil
        }
        return firstURL(in: payload)
    }

    private static func firstIPv4URL(in text: String) -> URL? {
        let pattern = #"https?://(?:127\.0\.0\.1|localhost)(?::\d+)?(?:/[^\s]*)?(?:\?[^\s]*)?(?:#[^\s]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let r = Range(match.range, in: text) {
            return URL(string: String(text[r]))
        }
        return nil
    }

    // MARK: - 通用

    private static func firstURL(in text: String) -> URL? {
        let pattern = #"https?://(?:\[[^\]]+\]|[^\s\)\]<>\"])+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let r = Range(match.range, in: text) {
            return URL(string: String(text[r]))
        }
        return nil
    }
}
