import Foundation

/// AstrBot 预设
///
/// AstrBot 是「持有子进程」模式：daemon 化启动，launcher 退出后它继续运行。
public enum AstrBotPreset {
    public static let identifier = "preset.astrbot"

    /// AstrBot 的候选安装位置（uv tool 安装优先）
    public static func candidateExecutables() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/astrbot",
            "\(home)/.local/share/uv/tools/astrbot/bin/astrbot",
            "/opt/homebrew/bin/astrbot",
            "/usr/local/bin/astrbot"
        ]
    }

    /// 存活检测用的命令行匹配模式
    public static func processMatchPatterns() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/astrbot run",
            "\(home)/.local/share/uv/tools/astrbot/bin/astrbot run",
            "/opt/homebrew/bin/astrbot run",
            "/usr/local/bin/astrbot run"
        ]
    }

    /// 探测到的 AstrBot 可执行文件路径
    public static func detectExecutable() -> String? {
        for candidate in candidateExecutables() where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    /// 构造 AstrBot 描述符
    /// - Parameters:
    ///   - webPort: WebUI 端口（用于端口探测）
    ///   - logPath: AstrBot 日志文件路径
    ///   - dataDirectory: AstrBot 数据目录（其**父目录**才是启动时的 cwd）
    public static func makeDescriptor(
        webPort: Int = 6185,
        logPath: String = "\(NSHomeDirectory())/data/logs/astrbot.log",
        dataDirectory: String = "\(NSHomeDirectory())/data"
    ) -> ServiceDescriptor {
        let executable = detectExecutable() ?? candidateExecutables()[0]
        let workingDirectory = PathExpander.parentDirectory(of: dataDirectory)

        return ServiceDescriptor(
            name: "AstrBot",
            lifecycle: .managed,
            enabled: true,
            autoStart: true,
            appearance: Appearance(iconSymbol: "gearshape.2.fill", accent: .orange),
            managed: .process(ProcessSpec(
                executable: executable,
                arguments: ["run"],
                workingDirectory: workingDirectory,
                environment: [:],
                shellMode: false,
                ownership: .daemon,
                processMatch: processMatchPatterns()
            )),
            probes: [
                .processPattern(processMatchPatterns()[0]),
                .tcpPort(webPort)
            ],
            logSources: [
                .file(id: "astrbot-log", label: "AstrBot 日志", path: logPath, webUIKind: .astrbot)
            ],
            openURL: URL(string: "http://localhost:\(webPort)"),
            note: "AI 机器人框架",
            presetIdentifier: identifier
        )
    }
}
