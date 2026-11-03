import SwiftUI
import AppKit

/// 设置面板 - 以 sheet 形式从主窗口弹出
///
/// 布局原则：
/// - 标签在输入框上方（更现代的移动端风格）
/// - 每节顶部有图标 + 标题 + 简介
/// - 关键操作有"快速操作"按钮
/// - 状态信息直接显示在相关设置旁
struct SettingsSheet: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            content
        }
        .frame(width: 580, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.title3.weight(.semibold))
                Text("AstrBot Launcher 配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .frame(minWidth: 50)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                generalSection
                astrBotSection
                dockerSection
                pathsSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        SettingsCard(title: "通用", icon: "gearshape.fill", tint: .gray) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsRow(title: "主题", description: "应用外观") {
                    Picker("", selection: $settings.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                Divider().opacity(0.3)

                SettingsRow(title: "状态轮询", description: "检查服务状态的频率") {
                    HStack(spacing: 6) {
                        TextField("", value: $settings.pollingInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.center)
                        Text("秒")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Stepper("", value: $settings.pollingInterval, in: 1...60, step: 1)
                            .labelsHidden()
                    }
                    .onChange(of: settings.pollingInterval) { _, _ in
                        appState.restartPolling()
                    }
                }

                Divider().opacity(0.3)

                SettingsToggleRow(
                    title: "开机自动启动",
                    description: "登录 macOS 时自动运行此 app",
                    isOn: $settings.autoStartOnBoot,
                    onChange: { LoginItemManager.shared.setEnabled($0) }
                )

                SettingsToggleRow(
                    title: "启动时最小化到 Dock",
                    description: "从登录项启动时不弹出主窗口",
                    isOn: $settings.startMinimized
                )

                SettingsToggleRow(
                    title: "启动时自动运行全部服务",
                    description: "打开 app 时自动启动 AstrBot / NapCat / Shipyard",
                    isOn: $settings.autoStartAllServices
                )

                SettingsToggleRow(
                    title: "服务状态通知",
                    description: "服务启停时显示系统通知",
                    isOn: $settings.enableNotifications
                )
            }
        }
    }

    // MARK: - AstrBot

    private var astrBotSection: some View {
        SettingsCard(title: "AstrBot", icon: "gearshape.2.fill", tint: ServiceType.astrbot.accentColor) {
            VStack(alignment: .leading, spacing: 14) {
                // 当前状态
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(astrBotStatusColor)
                    Text("当前状态：")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(astrBotStatusText)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let pid = appState.services[.astrbot]?.pid {
                        Text("PID \(pid)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider().opacity(0.3)

                SettingsRow(title: "启动模式", description: "如何启动 AstrBot 进程") {
                    Picker("", selection: $settings.astrBotLaunchMode) {
                        ForEach(AstrBotLaunchMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                // 模式相关输入
                if settings.astrBotLaunchMode == .uvToolRun {
                    SettingsPathField(
                        label: "AstrBot 路径",
                        text: .constant(AstrBotController.detectAstrbotPath() ?? "未检测到"),
                        placeholder: "自动检测",
                        editable: false,
                        onBrowse: nil
                    )
                } else if settings.astrBotLaunchMode == .customCommand {
                    SettingsTextFieldRow(
                        title: "自定义命令",
                        description: "执行完整的 shell 命令",
                        text: $settings.astrBotCustomCommand,
                        placeholder: "cd /path && uv run astrbot run"
                    )
                } else if settings.astrBotLaunchMode == .executablePath {
                    SettingsPathFieldRow(
                        title: "可执行文件",
                        description: "AstrBot 可执行文件的绝对路径",
                        text: $settings.astrBotExecutablePath,
                        placeholder: "/path/to/astrbot",
                        onBrowse: { pickFile(for: .astrbotExecutable) }
                    )
                } else if settings.astrBotLaunchMode == .shellScript {
                    SettingsPathFieldRow(
                        title: "启动脚本",
                        description: "启动 AstrBot 的 shell 脚本",
                        text: $settings.astrBotScriptPath,
                        placeholder: "/path/to/launch.sh",
                        onBrowse: { pickFile(for: .astrbotScript) }
                    )
                }

                Divider().opacity(0.3)

                SettingsRow(title: "WebUI 端口", description: "AstrBot WebUI 端口（fallback）") {
                    HStack(spacing: 6) {
                        TextField("", value: $settings.astrBotWebPort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.center)
                        Stepper("", value: $settings.astrBotWebPort, in: 1...65535, step: 1)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private var astrBotStatusColor: Color {
        switch appState.services[.astrbot]?.status {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .error: return .red
        case .stopped, .unknown: return .gray
        case .none: return .gray
        }
    }

    private var astrBotStatusText: String {
        appState.services[.astrbot]?.status.displayName ?? "未知"
    }

    // MARK: - Docker

    private var dockerSection: some View {
        SettingsCard(title: "Docker 容器", icon: "shippingbox.fill", tint: ServiceType.napcat.accentColor) {
            VStack(alignment: .leading, spacing: 14) {
                containerRow(type: .napcat)
                containerRow(type: .shipyard)

                Divider().opacity(0.3)

                HStack {
                    Text("已发现 \(appState.allContainers.count) 个容器")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        Task { await appState.refreshContainerList() }
                    } label: {
                        Label("刷新列表", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func containerRow(type: ServiceType) -> some View {
        SettingsRow(title: type.displayName, description: type.subtitle) {
            Picker("", selection: Binding(
                get: { containerName(for: type) },
                set: { setContainerName(for: type, name: $0) }
            )) {
                Text("未选择").tag("")
                if !containersForType(type).isEmpty {
                    Divider()
                }
                ForEach(containersForType(type)) { c in
                    Text("\(c.name)").tag(c.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 200)
        }
    }

    private func containerName(for type: ServiceType) -> String {
        switch type {
        case .napcat: return settings.napcatContainer
        case .shipyard: return settings.shipyardContainer
        case .astrbot: return ""
        }
    }

    private func setContainerName(for type: ServiceType, name: String) {
        switch type {
        case .napcat: settings.napcatContainer = name
        case .shipyard: settings.shipyardContainer = name
        case .astrbot: break
        }
    }

    private func containersForType(_ type: ServiceType) -> [ContainerController.Container] {
        appState.allContainers.filter { $0.serviceType == type }
    }

    // MARK: - 路径

    private var pathsSection: some View {
        SettingsCard(title: "路径", icon: "folder.fill", tint: .blue) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsPathFieldRow(
                    title: "AstrBot 日志",
                    description: "AstrBot 自己写入的日志文件",
                    text: $settings.astrbotLogPath,
                    placeholder: "~/data/logs/astrbot.log",
                    onBrowse: { pickFile(for: .astrbotLogFile) }
                )

                Divider().opacity(0.3)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("数据目录")
                            .font(.system(size: 12, weight: .medium))
                        Text(settings.dataDirectory)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        appState.openDataDirectory()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("在 Finder 中显示")
                    Button {
                        pickFile(for: .dataDir)
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("更改目录")
                }
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        SettingsCard(title: "关于", icon: "info.circle.fill", tint: .secondary) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Service Hub")
                        .font(.system(size: 13, weight: .semibold))
                    Text("v1.0.0 · macOS 26 Tahoe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "https://github.com") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - File Picker

    private enum PickerTarget {
        case astrbotExecutable, astrbotScript, astrbotLogFile
        case manualCompose, dataDir
    }

    private func pickFile(for target: PickerTarget) {
        let panel = NSOpenPanel()
        switch target {
        case .manualCompose:
            panel.title = "选择 compose.yml"
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        case .dataDir:
            panel.title = "选择数据目录"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.directoryURL = URL(fileURLWithPath: settings.expandPath(settings.dataDirectory))
        default:
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        switch target {
        case .astrbotExecutable: settings.astrBotExecutablePath = path
        case .astrbotScript: settings.astrBotScriptPath = path
        case .astrbotLogFile: settings.astrbotLogPath = path
        case .manualCompose:
            if !settings.manualComposePaths.contains(path) {
                settings.manualComposePaths.append(path)
            }
        case .dataDir: settings.dataDirectory = path
        }
    }
}

// MARK: - 设置卡片（玻璃效果）

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
                    .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            )
        }
    }
}

// MARK: - 设置行（标签 + 描述 + 控件）

struct SettingsRow<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 140, alignment: .leading)
            Spacer()
            content()
        }
    }
}

// MARK: - 设置行 - 文本输入

struct SettingsTextFieldRow: View {
    let title: String
    let description: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

// MARK: - 设置行 - 路径输入

struct SettingsPathFieldRow: View {
    let title: String
    let description: String
    @Binding var text: String
    let placeholder: String
    let onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                Button {
                    onBrowse()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - 设置行 - 开关

struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 140, alignment: .leading)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: isOn) { _, newValue in
                    onChange?(newValue)
                }
        }
    }
}

// MARK: - 兼容旧版（保留以防外部引用）

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    var tintColor: Color = .accentColor
    @ViewBuilder let content: () -> Content

    var body: some View {
        SettingsCard(title: title, icon: icon, tint: tintColor) {
            content()
        }
    }
}

struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.system(size: 12))
        }
        .toggleStyle(.switch)
    }
}

struct SettingsPathField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var editable: Bool = true
    let onBrowse: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(!editable)
                if let onBrowse {
                    Button {
                        onBrowse()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}
