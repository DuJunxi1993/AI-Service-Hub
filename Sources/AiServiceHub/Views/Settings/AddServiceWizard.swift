import SwiftUI
import AppKit
import AiServiceHubCore

/// 添加服务向导
///
/// 三级选择：**生命周期** → **驱动方式** → **具体配置**。
struct AddServiceWizard: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) var dismiss

    @State private var step: Step = .lifecycle

    // 表单
    @State private var name: String = ""
    @State private var executable: String = ""
    @State private var arguments: String = ""
    @State private var workingDirectory: String = ""
    @State private var shellMode: Bool = false
    @State private var detached: Bool = true
    @State private var stopOnAppQuit: Bool = false
    @State private var logPath: String = ""
    @State private var processPattern: String = ""
    @State private var watchPort: Int = 0
    @State private var selectedContainerID: String?
    @State private var openURLString: String = ""
    @State private var probeMode: ProbeMode = .process

    enum Step {
        case lifecycle
        case driver
        case configure
    }

    enum ProbeMode: String, CaseIterable, Identifiable {
        case process
        case port
        case http

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .process: return "进程匹配"
            case .port: return "监听端口"
            case .http: return "HTTP 可达"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case .lifecycle: lifecycleStep
                    case .driver: driverStep
                    case .configure: configureStep
                    }
                }
                .padding(20)
            }
            Divider().opacity(0.2)
            footer
        }
        .frame(width: 560, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            if appModel.allContainers.isEmpty {
                await appModel.refreshContainers()
            }
        }
    }

    // MARK: - 头尾

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("添加服务")
                    .font(.title3.weight(.semibold))
                Text(stepDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepDescription: String {
        switch step {
        case .lifecycle: return "第 1 步 · 选择这个服务由谁管理"
        case .driver: return "第 2 步 · 选择怎么管理"
        case .configure: return "第 3 步 · 填写具体配置"
        }
    }

    private var footer: some View {
        HStack {
            if step != .lifecycle {
                Button("上一步") {
                    step = (step == .configure) ? .driver : .lifecycle
                }
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(step == .configure ? "添加" : "下一步") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(step == .configure && name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 第 1 步

    private var lifecycleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("这个服务应该由本程序管理吗？")
                .font(.system(size: 13, weight: .medium))

            ChoiceCard(
                title: "纯监控",
                subtitle: "只读取状态、日志与端口，不启动也不停止它",
                icon: "eye.fill",
                tint: .gray,
                isSelected: false,
                action: { chooseLifecycle(.observed) }
            )

            ChoiceCard(
                title: "可管理",
                subtitle: "由本程序负责启动与停止（子进程或 Docker 容器）",
                icon: "bolt.fill",
                tint: .blue,
                isSelected: false,
                action: { chooseLifecycle(.managed) }
            )
        }
    }

    private func chooseLifecycle(_ mode: LifecycleMode) {
        if mode == .observed {
            driverSelection = nil
            step = .configure
        } else {
            step = .driver
        }
    }

    // MARK: - 第 2 步

    private var driverStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("用哪种方式管理？")
                .font(.system(size: 13, weight: .medium))

            ChoiceCard(
                title: "持有子进程",
                subtitle: "由本程序启动这个程序并持有 PID，可以停止与重启",
                icon: "terminal.fill",
                tint: .blue,
                isSelected: false,
                action: {
                    driverSelection = .process
                    step = .configure
                }
            )

            ChoiceCard(
                title: "委托 Docker 容器",
                subtitle: "由本程序执行 docker start/stop，进程由 dockerd 托管",
                icon: "shippingbox.fill",
                tint: .cyan,
                isSelected: false,
                action: {
                    driverSelection = .container
                    step = .configure
                }
            )
        }
    }

    // MARK: - 第 3 步

    @ViewBuilder
    private var configureStep: some View {
        switch selectedDriver {
        case .process: processForm
        case .container: containerForm
        case nil: observedForm
        }
    }

    /// 用户选择的驱动方式（纯监控服务为 nil）
    @State private var driverSelection: ManagedDriver?

    private var selectedDriver: ManagedDriver? {
        driverSelection
    }

    private var processForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsTextFieldRow(
                title: "名称",
                description: "显示在侧边栏里的名字",
                text: $name,
                placeholder: "My Service"
            )

            SettingsPathFieldRow(
                title: "可执行文件",
                description: "程序的绝对路径",
                text: $executable,
                placeholder: "/usr/local/bin/myapp",
                onBrowse: { pickFile() }
            )

            SettingsTextFieldRow(
                title: "参数",
                description: "用空格分隔",
                text: $arguments,
                placeholder: "--port 8080"
            )

            SettingsPathFieldRow(
                title: "工作目录",
                description: "启动时的当前目录（留空则继承）",
                text: $workingDirectory,
                placeholder: "/Users/me/myapp",
                onBrowse: { pickDirectory() }
            )

            SettingsTextFieldRow(
                title: "日志文件",
                description: "要跟随的日志文件（留空则不显示日志）",
                text: $logPath,
                placeholder: "/Users/me/myapp/logs/app.log"
            )

            SettingsTextFieldRow(
                title: "存活检测",
                description: "用于判断进程是否在运行的命令行匹配片段",
                text: $processPattern,
                placeholder: "myapp --serve"
            )

            VStack(alignment: .leading, spacing: 8) {
                Toggle("经由 shell 执行", isOn: $shellMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("关闭时直接执行程序；开启后 `&&`、`|` 等 shell 语法才生效。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Toggle("daemon 化（脱离本程序独立运行）", isOn: $detached)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("本程序退出时终止它", isOn: $stopOnAppQuit)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .font(.system(size: 12))
        }
    }

    private var containerForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appModel.allContainers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("没有发现 Docker 容器，请先确认 Docker Desktop 已启动。")
                        .font(.system(size: 12))
                    Spacer()
                    Button("重新检测") {
                        Task { await appModel.refreshContainers() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("选择容器")
                        .font(.system(size: 12, weight: .medium))
                    Text("本程序只管理已存在的容器，不会创建新的。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedContainerID) {
                        Text("未选择").tag(String?.none)
                        ForEach(appModel.allContainers) { container in
                            Text("\(container.name)  ·  \(container.image)")
                                .tag(String?.some(container.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 380)
                }
            }

            SettingsTextFieldRow(
                title: "显示名称",
                description: "留空则使用容器名",
                text: $name,
                placeholder: "My Container"
            )

            Toggle("本程序退出时停止该容器", isOn: $stopOnAppQuit)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
        }
    }

    private var observedForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsTextFieldRow(
                title: "名称",
                description: "显示在侧边栏里的名字",
                text: $name,
                placeholder: "My Monitor"
            )

            SettingsPathFieldRow(
                title: "日志文件",
                description: "要跟随的日志文件（留空则不显示日志）",
                text: $logPath,
                placeholder: "/Users/me/.myapp/app.log",
                onBrowse: { pickLogFile() }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("探测方式")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $probeMode) {
                    ForEach(ProbeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)

                switch probeMode {
                case .process:
                    TextField("命令行匹配片段，例如 hermes gateway run", text: $processPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                case .port:
                    HStack {
                        TextField("端口", value: $watchPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("只读监控不会判断这个端口属于谁，请自行确认。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                case .http:
                    TextField("http://127.0.0.1:3080/", text: $openURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Text("返回 401 也视为「可达」—— 只说明服务在运行。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsTextFieldRow(
                title: "打开地址（可选）",
                description: "点击「打开 WebUI」时使用的地址",
                text: $openURLString,
                placeholder: "http://127.0.0.1:3080"
            )
        }
    }

    /// 按容器名或镜像推断 WebUI 地址的提取规则
    ///
    /// NapCat 会在日志里打印带 token 的 WebUI 地址；
    /// 其余容器暂无已知格式，留 nil（不提取）。
    private static func webUIKind(forContainer container: DockerContainer) -> WebUIKind? {
        let haystack = (container.name + " " + container.image).lowercased()
        if haystack.contains("napcat") { return .napCat }
        return nil
    }

    // MARK: - 提交

    private func advance() {
        switch step {
        case .lifecycle:
            step = .driver
        case .driver:
            step = .configure
        case .configure:
            createService()
        }
    }

    private func createService() {
        let descriptor = buildDescriptor()
        guard descriptor != nil else { return }
        settings.add(descriptor!)
        dismiss()
    }

    private func buildDescriptor() -> ServiceDescriptor? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        switch driverSelection {
        case .process:
            let exe = executable.trimmingCharacters(in: .whitespaces)
            guard !exe.isEmpty else { return nil }
            let spec = ProcessSpec(
                executable: exe,
                arguments: arguments.split(separator: " ").map(String.init),
                workingDirectory: workingDirectory.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : workingDirectory,
                environment: [:],
                shellMode: shellMode,
                ownership: ProcessOwnership(detached: detached, stopOnAppQuit: stopOnAppQuit),
                processMatch: processPattern.isEmpty ? [exe] : [processPattern]
            )
            var logSources: [LogSourceSpec] = []
            if !logPath.trimmingCharacters(in: .whitespaces).isEmpty {
                logSources.append(.file(id: "logs", label: "日志", path: logPath))
            }
            return ServiceDescriptor(
                name: trimmedName,
                lifecycle: .managed,
                enabled: true,
                autoStart: false,
                appearance: Appearance(iconSymbol: "terminal.fill", accent: .green),
                managed: .process(spec),
                probes: [.processPattern(spec.processMatch[0])],
                logSources: logSources,
                openURL: nil
            )

        case .container:
            guard let selectedContainerID,
                  let container = appModel.allContainers.first(where: { $0.id == selectedContainerID }) else {
                return nil
            }
            return ServiceDescriptor(
                name: trimmedName.isEmpty ? container.name : trimmedName,
                lifecycle: .managed,
                enabled: true,
                autoStart: false,
                appearance: Appearance(iconSymbol: "shippingbox.fill", accent: .cyan),
                managed: .container(ContainerSpec(
                    containerName: container.name,
                    composePath: nil,
                    stopOnAppQuit: stopOnAppQuit
                )),
                probes: [],
                logSources: [
                    .dockerLogs(
                        id: "container-logs",
                        label: "容器日志",
                        containerName: container.name,
                        webUIKind: Self.webUIKind(forContainer: container)
                    )
                ],
                openURL: nil
            )

        case .none:
            // 纯监控
            var logSources: [LogSourceSpec] = []
            if !logPath.trimmingCharacters(in: .whitespaces).isEmpty {
                logSources.append(.file(id: "logs", label: "日志", path: logPath))
            }
            var probes: [Probe] = []
            switch probeMode {
            case .process:
                if !processPattern.isEmpty { probes.append(.processPattern(processPattern)) }
            case .port:
                if watchPort > 0 { probes.append(.tcpPort(watchPort)) }
            case .http:
                if !openURLString.isEmpty { probes.append(.httpReachability(openURLString)) }
            }
            return ServiceDescriptor(
                name: trimmedName,
                lifecycle: .observed,
                enabled: true,
                autoStart: false,
                appearance: Appearance(iconSymbol: "eye.fill", accent: .purple),
                managed: nil,
                probes: probes,
                logSources: logSources,
                openURL: openURLString.isEmpty ? nil : URL(string: openURLString),
                note: "纯监控（不接管进程）"
            )
        }
    }

    // MARK: - 文件选择

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        executable = url.path
    }

    private func pickLogFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        logPath = url.path
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDirectory = url.path
    }
}

/// 选择卡片
struct ChoiceCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}
