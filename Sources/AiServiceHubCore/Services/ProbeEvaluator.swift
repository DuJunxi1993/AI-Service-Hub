import Foundation

/// 探测执行器 —— 把 `Probe` 变成 `ProbeResult`
public struct ProbeEvaluator: Sendable {
    private let runner: CommandRunner
    private let inspector: ProcessInspector

    public init(runner: CommandRunner = CommandRunner(), inspector: ProcessInspector = ProcessInspector()) {
        self.runner = runner
        self.inspector = inspector
    }

    /// 执行一次探测
    /// - Parameter table: 本轮已枚举好的进程表；为空时自行枚举
    public func evaluate(_ probe: Probe, table: ProcessTable? = nil) async -> ProbeResult {
        switch probe {
        case .processPattern(let pattern):
            return await evaluateProcessPattern(pattern, table: table)
        case .tcpPort(let port):
            return await evaluatePort(port)
        case .httpReachability(let urlString):
            return await evaluateHTTP(urlString)
        case .fileExists(let path):
            return evaluateFile(path)
        case .jsonState(let path, let key):
            return evaluateJSONState(path: path, key: key)
        case .hermesGateway(let path):
            return await evaluateHermesGateway(path: path)
        }
    }

    // MARK: - 各类探测

    private func evaluateProcessPattern(_ pattern: String, table: ProcessTable?) async -> ProbeResult {
        let processes: [ProcessSnapshot]
        if let table {
            processes = table.matching([pattern])
        } else {
            processes = await inspector.allProcesses(matching: [pattern])
        }
        guard let first = processes.first else {
            return ProbeResult(label: "进程", state: .failed, summary: "未运行")
        }
        var groups: [DetailGroup] = []
        if processes.count > 1 {
            groups.append(DetailGroup(
                title: "同名进程",
                rows: processes.map {
                    DetailRow(label: "PID \($0.pid)", value: $0.command)
                }
            ))
        }
        return ProbeResult(
            label: "进程",
            state: .ok,
            summary: "运行中 (PID \(first.pid))",
            groups: groups
        )
    }

    private func evaluatePort(_ port: Int) async -> ProbeResult {
        let listening = await inspector.isPortListening(port)
        return ProbeResult(
            label: "端口 \(port)",
            state: listening ? .ok : .failed,
            summary: listening ? "监听中" : "未监听"
        )
    }

    private func evaluateHTTP(_ urlString: String) async -> ProbeResult {
        guard let url = URL(string: urlString) else {
            return ProbeResult(label: "HTTP 可达性", state: .failed, summary: "地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 需要鉴权的服务返回 401 也说明「服务在跑」
            let state: ProbeState = (200..<500).contains(code) ? .ok : .warning
            return ProbeResult(
                label: "HTTP 可达性",
                state: state,
                summary: "可访问 (HTTP \(code))"
            )
        } catch {
            return ProbeResult(label: "HTTP 可达性", state: .failed, summary: "无法连接")
        }
    }

    private func evaluateFile(_ path: String) -> ProbeResult {
        let expanded = PathExpander.expand(path)
        let exists = FileManager.default.fileExists(atPath: expanded)
        return ProbeResult(
            label: "文件",
            state: exists ? .ok : .failed,
            summary: exists ? expanded : "不存在"
        )
    }

    private func evaluateJSONState(path: String, key: String) -> ProbeResult {
        let expanded = PathExpander.expand(path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProbeResult(label: "状态 \(key)", state: .failed, summary: "无法读取状态文件")
        }
        guard let value = Self.flattenJSON(object)[key] else {
            return ProbeResult(label: "状态 \(key)", state: .unknown, summary: "字段缺失")
        }
        return ProbeResult(label: "状态 \(key)", state: .ok, summary: String(describing: value))
    }

    /// 解析 Hermes Gateway 状态文件
    private func evaluateHermesGateway(path: String) async -> ProbeResult {
        let expanded = PathExpander.expand(path)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ProbeResult(label: "Gateway", state: .failed, summary: "状态文件不存在")
        }

        let state = object["gateway_state"] as? String ?? "unknown"
        let pid = (object["pid"] as? NSNumber)?.int32Value
        let version = object["code_version"] as? String ?? "—"
        let activeAgents = (object["active_agents"] as? NSNumber)?.intValue ?? 0
        let sessionStore = (object["session_store"] as? [String: Any])?["status"] as? String ?? "—"

        var runtimeRows: [DetailRow] = []
        if let pid {
            runtimeRows.append(DetailRow(label: "PID", value: String(pid)))
            // Gateway 的 TCP 端口是动态分配的，必须按 pid 反查
            let ports = await inspector.listeningPorts(pid: pid)
            runtimeRows.append(DetailRow(
                label: "监听端口",
                value: ports.isEmpty ? "—" : ports.map(String.init).joined(separator: ", ")
            ))
        }
        runtimeRows.append(DetailRow(label: "活跃 Agent", value: String(activeAgents)))
        runtimeRows.append(DetailRow(label: "版本", value: version))
        runtimeRows.append(DetailRow(label: "会话存储", value: sessionStore))

        // 平台连接情况
        var platformRows: [DetailRow] = []
        if let platforms = object["platforms"] as? [String: Any] {
            for name in platforms.keys.sorted() {
                guard let info = platforms[name] as? [String: Any] else { continue }
                let platformState = info["state"] as? String ?? "unknown"
                let errorMessage = info["error_message"] as? String
                let updatedAt = info["updated_at"] as? String

                // 颜色只反映连接状态本身。「多久没更新」是另一回事，
                // 混进颜色会让两个都 connected 的平台显示成不同颜色。
                var rowState: ProbeState = switch platformState {
                case "connected": .ok
                case "disconnected", "error", "failed": .failed
                default: .unknown
                }
                if info["needs_attention"] as? Bool == true {
                    rowState = .warning
                }

                var value = platformState
                if let errorMessage, !errorMessage.isEmpty {
                    value += " · \(errorMessage)"
                }

                // 时间戳单独作为备注，不参与状态着色
                var note: String?
                if let updatedAt {
                    note = Self.relativeTimeDescription(from: updatedAt)
                    // 连接正常但很久没更新 —— 用备注提示，不改颜色
                    if rowState == .ok, note?.hasPrefix("很久") == true {
                        note = "\(note)（状态未更新）"
                    }
                }
                platformRows.append(DetailRow(label: name, value: value, state: rowState, note: note))
            }
        }

        var groups: [DetailGroup] = [DetailGroup(title: "运行时", rows: runtimeRows)]
        if !platformRows.isEmpty {
            groups.append(DetailGroup(title: "消息平台", rows: platformRows))
        }

        let summaryState: ProbeState = state == "running" ? .ok : .failed
        return ProbeResult(
            label: "Gateway",
            state: summaryState,
            summary: state,
            groups: groups
        )
    }

    // MARK: - 工具

    /// 把 JSON 对象拍平成 "a.b.c" → value
    static func flattenJSON(_ object: [String: Any], prefix: String = "") -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any] {
                result.merge(flattenJSON(nested, prefix: path)) { _, new in new }
            } else {
                result[path] = value
            }
        }
        return result
    }

    /// 时间戳是否已经过时（超过 1 小时没更新）
    static func isStale(_ iso8601: String, threshold: TimeInterval = 3600) -> Bool {
        guard let date = parseTimestamp(iso8601) else { return false }
        return Date().timeIntervalSince(date) > threshold
    }

    /// 解析 ISO8601 时间戳（带或不带小数秒）
    static func parseTimestamp(_ iso8601: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso8601) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso8601)
    }

    /// 相对时间描述，例如「3 分钟前」「2 小时前」「很久以前」
    static func relativeTimeDescription(from iso8601: String) -> String? {
        guard let date = parseTimestamp(iso8601) else { return nil }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 0 { return "刚刚" }
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) 分钟前" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600)) 小时前" }
        if elapsed < 86400 * 30 { return "\(Int(elapsed / 86400)) 天前" }
        return "很久以前"
    }
}
