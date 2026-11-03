import Foundation

/// 已知日志格式的 WebUI 提取策略
public enum WebUIKind: String, Sendable, Hashable, CaseIterable {
    case astrbot
    case napCat
}

/// 从日志行中检测 WebUI URL
/// 根据服务类型使用不同的模式：
/// - AstrBot: "Starting WebUI at <URL>" 或 "Local: <URL>"（显式排除 "Network:"）
/// - NapCat: "WebUi User Panel Url: <URL>"（只取 IPv4 127.0.0.1，跳过 IPv6 [::]）
public enum WebUIURLDetector {
    /// 统一入口
    public static func extract(from line: String, for kind: WebUIKind) -> URL? {
        switch kind {
        case .astrbot:
            return extractAstrBotURL(from: line)
        case .napCat:
            return extractNapCatURL(from: line)
        }
    }

    // MARK: - AstrBot

    static func extractAstrBotURL(from line: String) -> URL? {
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

    static func extractNapCatURL(from line: String) -> URL? {
        guard let range = line.range(of: "WebUi User Panel Url: ", options: .caseInsensitive) else {
            return nil
        }
        let payload = String(line[range.upperBound...])
        // 只接受 IPv4 / localhost：IPv6 的 [::1] 在浏览器里打不开
        return firstIPv4URL(in: payload)
    }

    static func firstIPv4URL(in text: String) -> URL? {
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

    static func firstURL(in text: String) -> URL? {
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
