import Foundation

/// DeepSeek Harness 预设（**纯监控**）
///
/// 本程序不启动、不停止、不持有 DSH 的任何进程，只读取：
/// - `dsh web` 进程与其 `--port` 参数
/// - DSHShell 原生外壳进程
/// - HTTP 可达性（DSH 所有路径都需要鉴权，401 也算「可达」）
/// - 启动日志与会话目录
public enum DSHPreset {
    public static let identifier = "preset.dsh"

    public static func defaultHome() -> String {
        "\(NSHomeDirectory())/.dsh"
    }

    /// 构造 DSH 描述符
    public static func makeDescriptor(home: String = DSHPreset.defaultHome(), port: Int = 3080) -> ServiceDescriptor {
        let shellPath = "/Applications/DSHShell.app/Contents/MacOS/DSHShell"

        return ServiceDescriptor(
            name: "DeepSeek Harness",
            lifecycle: .observed,
            enabled: true,
            autoStart: false,
            appearance: Appearance(iconSymbol: "terminal.fill", accent: .cyan),
            managed: nil,
            probes: [
                .processPattern("dsh web"),
                .processPattern("DSHShell"),
                .httpReachability("http://127.0.0.1:\(port)/")
            ],
            logSources: [
                .filePattern(id: "dsh-startup", label: "启动日志", pattern: "\(home)/logs/startup-*.log"),
                .file(id: "dsh-skills", label: "Skills 管理器", path: "\(home)/dsh-skills-manager.log")
            ],
            openURL: URL(string: "http://127.0.0.1:\(port)"),
            note: "DeepSeek Harness Web 控制台（只读监控）",
            presetIdentifier: identifier
        )
    }
}
