import Foundation

/// 服务的端口映射（从 docker compose 解析）
struct ServicePortInfo {
    let serviceName: String
    let hostIP: String      // "0.0.0.0" / "127.0.0.1" / ""（全部接口）
    let hostPort: Int
    let containerPort: Int
}

/// 从 docker compose yml 解析端口映射
///
/// 解析 `ports:` 字段的多种格式：
///   - `"8156:8156"`  → host=8156, container=8156
///   - `"127.0.0.1:6099:6099"` → host=6099, container=6099
///   - `"8156"`  → host=8156, container=8156 (省略 container port)
///   - `range: "8156-8160:8156-8160"` → 展开为多个端口
enum DockerComposePortParser {
    /// 从 compose 文件获取指定服务的所有端口映射
    static func ports(fromComposePath path: String, serviceName: String) -> [ServicePortInfo] {
        let expanded = (path as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            return []
        }
        return parseServicePorts(yaml: content, serviceName: serviceName)
    }

    /// 核心解析逻辑
    static func parseServicePorts(yaml: String, serviceName: String) -> [ServicePortInfo] {
        let lines = yaml.components(separatedBy: "\n")
        var inServices = false
        var inTargetService = false
        var inPorts = false
        var targetIndent = -1
        var portsIndent = -1
        var result: [ServicePortInfo] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let leadingSpaces = line.prefix(while: { $0 == " " }).count

            // 跳过空行和注释
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // 顶级 services: 块
            if leadingSpaces == 0 {
                if trimmed == "services:" {
                    inServices = true
                    inTargetService = false
                } else if inServices {
                    inServices = false
                }
                continue
            }

            // 在 services 块内
            if inServices {
                // 检测服务名（2 空格缩进）
                if leadingSpaces == 2 {
                    let name = trimmed.replacingOccurrences(of: ":", with: "")
                    inTargetService = (name == serviceName)
                    inPorts = false
                    if inTargetService {
                        targetIndent = leadingSpaces
                    }
                    continue
                }

                // 在目标服务内
                if inTargetService {
                    // ports: 字段（与 serviceName 同缩进，或多 2 空格）
                    if leadingSpaces == targetIndent + 2 && trimmed == "ports:" {
                        inPorts = true
                        portsIndent = leadingSpaces
                        continue
                    }

                    // 退出 ports 块
                    if inPorts && leadingSpaces <= portsIndent {
                        inPorts = false
                    }

                    // 解析 port 行（在 ports 块内，缩进 = portsIndent + 2）
                    if inPorts && leadingSpaces >= portsIndent + 2 && trimmed.hasPrefix("-") {
                        let portSpec = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                        if let info = parsePortSpec(portSpec) {
                            result.append(info)
                        }
                    }

                    // 退出目标服务（遇到顶层其他字段）
                    if leadingSpaces <= targetIndent && !trimmed.hasPrefix("-") {
                        inTargetService = false
                    }
                }
            }
        }

        return result
    }

    /// 解析单个端口规格
    /// - "8156:8156" → host=8156, container=8156
    /// - "127.0.0.1:6099:6099" → host=6099, container=6099
    /// - "8156" → host=8156, container=8156
    /// - "8156-8160:8156-8160" → 展开
    private static func parsePortSpec(_ spec: String) -> ServicePortInfo? {
        // 移除引号
        let cleaned = spec.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")

        // 检查是否是短语法（只指定 container port）
        if !cleaned.contains(":") {
            // "8156" - 短语法
            if let port = Int(cleaned) {
                return ServicePortInfo(
                    serviceName: "",
                    hostIP: "",
                    hostPort: port,
                    containerPort: port
                )
            }
            return nil
        }

        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: true).map(String.init)

        // 3 段: "IP:HOST:CONTAINER" 或 "HOST:CONTAINER:PROTOCOL"
        // 2 段: "HOST:CONTAINER"
        switch parts.count {
        case 2:
            // "HOST:CONTAINER"
            let hostParts = parts[0].contains("-") ? expandRange(parts[0]) : [parts[0]]
            let containerParts = parts[1].contains("-") ? expandRange(parts[1]) : [parts[1]]

            var result: [ServicePortInfo] = []
            for (i, host) in hostParts.enumerated() {
                let container = i < containerParts.count ? containerParts[i] : host
                if let h = Int(host), let c = Int(container) {
                    result.append(ServicePortInfo(
                        serviceName: "",
                        hostIP: "",
                        hostPort: h,
                        containerPort: c
                    ))
                }
            }
            return result.first  // 简化：只返回第一个（compose port 通常是 1 对 1）

        case 3:
            // 判断是否 "IP:HOST:CONTAINER" 或 "HOST:CONTAINER:PROTO"
            if isIPAddress(parts[0]) {
                // "127.0.0.1:6099:6099"
                if let h = Int(parts[1]), let c = Int(parts[2]) {
                    return ServicePortInfo(
                        serviceName: "",
                        hostIP: parts[0],
                        hostPort: h,
                        containerPort: c
                    )
                }
            } else {
                // "HOST:CONTAINER:PROTOCOL" (如 "8156:8156:tcp")
                if let h = Int(parts[0]), let c = Int(parts[1]) {
                    return ServicePortInfo(
                        serviceName: "",
                        hostIP: "",
                        hostPort: h,
                        containerPort: c
                    )
                }
            }
            return nil

        default:
            return nil
        }
    }

    /// 展开端口范围 "8156-8158" → ["8156", "8157", "8158"]
    private static func expandRange(_ range: String) -> [String] {
        let parts = range.split(separator: "-")
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              start <= end else {
            return [range]
        }
        return (start...end).map { String($0) }
    }

    /// 判断字符串是否是 IP 地址
    private static func isIPAddress(_ s: String) -> Bool {
        // 简单判断：包含 . 或 :
        s.contains(".") || s.contains(":")
    }
}
