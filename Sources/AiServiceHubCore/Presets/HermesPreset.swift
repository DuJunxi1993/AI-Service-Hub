import Foundation

/// Hermes Agent 预设（**纯监控**）
///
/// 本程序不启动、不停止、不持有 Hermes 的任何进程，只读取：
/// - Gateway 状态文件（运行状态、平台连接情况）
/// - Gateway / agent 日志
/// - Gateway 进程与其监听端口（端口是动态分配的，由 pid 反查）
public enum HermesPreset {
    public static let identifier = "preset.hermes"

    public static func defaultHome() -> String {
        "\(NSHomeDirectory())/.hermes"
    }

    /// 构造 Hermes 描述符
    public static func makeDescriptor(home: String = HermesPreset.defaultHome()) -> ServiceDescriptor {
        let statePath = "\(home)/gateway_state.json"

        return ServiceDescriptor(
            name: "Hermes Agent",
            lifecycle: .observed,
            enabled: true,
            autoStart: false,
            appearance: Appearance(iconSymbol: "antenna.radiowaves.left.and.right", accent: .purple),
            managed: nil,
            probes: [
                .hermesGateway(path: statePath),
                .processPattern("hermes gateway run")
            ],
            logSources: [
                .file(id: "hermes-gateway", label: "Gateway", path: "\(home)/logs/gateway.log"),
                .file(id: "hermes-gateway-error", label: "Gateway 错误", path: "\(home)/logs/gateway.error.log"),
                .file(id: "hermes-agent", label: "Agent", path: "\(home)/logs/agent.log")
            ],
            openURL: nil,
            note: "消息网关与 Agent 运行时（只读监控）",
            presetIdentifier: identifier
        )
    }
}
