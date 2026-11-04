import SwiftUI
import AiServiceHubCore

/// 服务详情视图 - 玻璃头部 + 左侧信息/按钮 + 右侧日志面板
///
/// 布局：
/// - 常规：左栏放元数据、探测结果与操作按钮；右栏是**竖直**的日志面板（标题在上）
/// - 展开：日志面板改为**横向**铺满整个下半部分
struct ServiceDetailView: View {
    let descriptor: ServiceDescriptor

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var isLogExpanded: Bool = false
    /// 「停止全部进程」的二次确认
    @State private var showsStopAllConfirmation: Bool = false

    private var snapshot: ServiceSnapshot {
        appModel.snapshots[descriptor.id] ?? ServiceSnapshot(descriptorID: descriptor.id)
    }

    /// 详情区窄于此宽度时，日志改为横向铺满（否则两个面板会互相挤掉）
    private static let horizontalLogThreshold: CGFloat = 560

    var body: some View {
        GeometryReader { geometry in
            let stackVertically = isLogExpanded || geometry.size.width < Self.horizontalLogThreshold

            VStack(spacing: 0) {
                headerCard

                Divider()
                    .opacity(0.2)
                    .padding(.vertical, 8)

                if stackVertically {
                    // 横向：信息在上，日志铺满整个下半部分
                    VStack(spacing: 0) {
                        infoPane
                            .frame(maxHeight: .infinity)

                        Divider()
                            .opacity(0.2)

                        InlineLogView(
                            descriptor: descriptor,
                            isExpanded: true,
                            onToggleExpanded: { withAnimation(Theme.springAnimation) { isLogExpanded = false } }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 常规：左信息 / 右竖直日志
                    //
                    // 宽度预算：窗口最小 820 − 侧栏最小 170 = 650 给详情区，
                    // 两个子面板的最小宽度之和（260 + 220 = 480）必须小于它，
                    // 否则内容会被裁掉。
                    HSplitView {
                        infoPane
                            .frame(minWidth: 260, idealWidth: 440, maxWidth: .infinity)

                        logPane
                            .frame(minWidth: 220, idealWidth: 400, maxWidth: 720)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()
                    .opacity(0.2)

                StatusBarView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .confirmationDialog(
            "停止 \(descriptor.name) 的全部进程？",
            isPresented: $showsStopAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("终止全部进程", role: .destructive) {
                Task { await appModel.stopAllProcesses(of: descriptor.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(stopAllWarning)
        }
    }

    /// 终止前的说明
    private var stopAllWarning: String {
        let patterns = descriptor.effectiveStopPatterns
        let matched = appModel.matchingProcessCount(for: descriptor.id)
        var text = "将终止匹配以下规则的进程：\n\(patterns.joined(separator: "\n"))"
        text += "\n\n当前匹配到 \(matched) 个进程。此操作不可撤销。"
        if descriptor.presetIdentifier == DSHPreset.identifier {
            text += "\n\n注意：DSH 的 Web 控制台进程也在其中，停止后本程序会失去与它的连接。"
        }
        return text
    }

    /// 左栏：元数据 + 探测结果 + 操作按钮
    private var infoPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadataRows

                if !snapshot.probeResults.isEmpty {
                    Divider().opacity(0.3)
                    probeSection
                }

                actionButtons

                if snapshot.webURL == nil, descriptor.lifecycle == .managed {
                    webUIPendingHint
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// WebUI 地址尚未解析到时的提示
    private var webUIPendingHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(webUIUnavailableHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// 右栏：竖直日志面板
    private var logPane: some View {
        InlineLogView(
            descriptor: descriptor,
            isExpanded: false,
            onToggleExpanded: { withAnimation(Theme.springAnimation) { isLogExpanded = true } }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 头部卡片

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: descriptor.appearance.iconSymbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(descriptor.name)
                        .font(.title2.weight(.semibold))

                    HStack(spacing: 4) {
                        StatusDot(status: snapshot.status)
                        Text(snapshot.status.displayName)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusBadgeColor.opacity(0.15)))

                    // 生命周期徽章
                    HStack(spacing: 3) {
                        Image(systemName: descriptor.lifecycle == .observed ? "eye.fill" : "bolt.fill")
                            .font(.system(size: 8))
                        Text(modeBadgeText)
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    .foregroundStyle(.secondary)
                    .help(descriptor.lifecycle.summary)
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let error = snapshot.lastError, snapshot.status == .error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .trailing)
            }
        }
        .padding(Theme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.tint(accentColor.opacity(0.08)), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var modeBadgeText: String {
        switch descriptor.lifecycle {
        case .observed: return "纯监控"
        case .managed:
            switch descriptor.driver {
            case .process: return "持有子进程"
            case .container: return "委托容器"
            case nil: return "可管理"
            }
        }
    }

    private var accentColor: Color {
        Color(
            red: descriptor.appearance.accent.red,
            green: descriptor.appearance.accent.green,
            blue: descriptor.appearance.accent.blue
        )
    }

    private var statusBadgeColor: Color {
        switch snapshot.status {
        case .running: return .green
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .error: return .red
        case .degraded: return .orange
        case .unknown: return .gray
        }
    }

    private var subtitle: String {
        if let image = snapshot.image { return image }
        if let container = snapshot.containerName { return container }
        if let pid = snapshot.pid { return "PID: \(pid)" }
        return descriptor.note ?? descriptor.lifecycle.summary
    }

    /// WebUI 按钮不可用时的说明
    ///
    /// 光把按钮禁掉等于让用户猜原因，要说清楚是「还没解析到」
    /// 还是「这个服务的日志里本来就没有地址」。
    private var webUIUnavailableHint: String {
        let hasLogSource = !descriptor.logSources.isEmpty
        guard hasLogSource else {
            return "该服务没有配置日志来源，无法从日志中解析 WebUI 地址"
        }
        let hasExtractor = descriptor.logSources.contains { $0.webUIKind != nil }
        guard hasExtractor else {
            return "该服务的日志没有配置 WebUI 地址提取规则，无法自动解析"
        }
        switch snapshot.status {
        case .running:
            return "正在从日志中解析 WebUI 地址，请稍候或检查服务日志里是否打印了地址"
        case .stopped:
            return "服务未运行，启动后才会从日志中解析 WebUI 地址"
        default:
            return "尚未解析到 WebUI 地址"
        }
    }

    // MARK: - 元数据

    @ViewBuilder
    private var metadataRows: some View {
        switch descriptor.managed {
        case .process(let spec):
            VStack(alignment: .leading, spacing: 8) {
                MetadataRow(label: "进程 PID", value: snapshot.pid.map { String($0) } ?? "—")
                MetadataRow(label: "可执行文件", value: spec.executable)
                MetadataRow(label: "参数", value: spec.arguments.isEmpty ? "—" : spec.arguments.joined(separator: " "))
                MetadataRow(label: "工作目录", value: spec.workingDirectory ?? "继承")
                MetadataRow(label: "运行方式", value: spec.shellMode ? "经 shell 执行" : "直接执行")
                MetadataRow(
                    label: "退出行为",
                    value: spec.ownership.detached
                        ? (spec.ownership.stopOnAppQuit ? "daemon 化 · 退出时终止" : "daemon 化 · 退出后继续运行")
                        : (spec.ownership.stopOnAppQuit ? "随 app 退出" : "随 app 退出 · 保留进程")
                )
                if !snapshot.listeningPorts.isEmpty {
                    MetadataRow(label: "监听端口", value: snapshot.listeningPorts.map(String.init).joined(separator: ", "))
                }
                MetadataRow(label: "来源", value: snapshot.startedByUs ? "本程序启动" : "外部启动")
            }

        case .container(let spec):
            VStack(alignment: .leading, spacing: 8) {
                MetadataRow(label: "容器名", value: snapshot.containerName ?? spec.containerName)
                MetadataRow(label: "镜像", value: snapshot.image ?? "—")
                MetadataRow(label: "端口映射", value: snapshot.ports.isEmpty ? "—" : snapshot.ports.joined(separator: ", "))
                MetadataRow(label: "退出行为", value: spec.stopOnAppQuit ? "退出时停止容器" : "退出时保留容器")
            }

        case nil:
            VStack(alignment: .leading, spacing: 8) {
                MetadataRow(label: "生命周期", value: "纯监控（不接管进程）")
                if let pid = snapshot.pid {
                    MetadataRow(label: "进程 PID", value: String(pid))
                }
                if !snapshot.listeningPorts.isEmpty {
                    MetadataRow(label: "监听端口", value: snapshot.listeningPorts.map(String.init).joined(separator: ", "))
                }
                MetadataRow(label: "说明", value: descriptor.note ?? "—")
            }
        }
    }

    private var probeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("探测结果")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(snapshot.probeResults) { result in
                ProbeResultView(result: result)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            // 左侧留白，按钮靠右排布
            Spacer(minLength: 0)

            if descriptor.lifecycle == .managed {
                Button {
                    Task { await appModel.start(descriptor.id) }
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.startColor)
                .disabled(!snapshot.status.canStart)
                .controlSize(.large)
                .fixedSize()

                Button(role: .destructive) {
                    Task { await appModel.stop(descriptor.id) }
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.stopColor)
                .disabled(!snapshot.status.canStop)
                .controlSize(.large)
                .fixedSize()

                Button {
                    Task { await appModel.restart(descriptor.id) }
                } label: {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(snapshot.status == .stopped || snapshot.status == .unknown)
                .controlSize(.large)
                .fixedSize()
            } else {
                // 纯监控服务：没有驱动，但用户仍可能想一键停掉它
                Button(role: .destructive) {
                    showsStopAllConfirmation = true
                } label: {
                    Label("停止全部进程", systemImage: "xmark.octagon.fill")
                }
                .buttonStyle(.glass)
                .disabled(descriptor.effectiveStopPatterns.isEmpty || snapshot.status == .stopped)
                .controlSize(.large)
                .fixedSize()
                .help(descriptor.effectiveStopPatterns.isEmpty
                      ? "该服务没有配置进程匹配规则"
                      : "终止匹配该服务进程规则的全部进程（\(descriptor.effectiveStopPatterns.count) 条规则）")
            }

            Button {
                appModel.openWebUI(descriptor.id)
            } label: {
                Label("打开 WebUI", systemImage: "safari")
            }
            .buttonStyle(.glassProminent)
            .disabled(snapshot.webURL == nil)
            .controlSize(.large)
            .fixedSize()
            .help(snapshot.webURL?.absoluteString ?? webUIUnavailableHint)

            if let dataDirectory = descriptor.dataDirectory {
                Button {
                    appModel.openDataDirectory(of: descriptor.id)
                } label: {
                    Label("数据目录", systemImage: "folder")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .fixedSize()
                .help("在 Finder 中打开 \(dataDirectory)")
            }
        }
        .padding(.top, 8)
    }
}

/// 探测结果卡片
struct ProbeResultView: View {
    let result: ProbeResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(result.label)
                    .font(.system(size: 12, weight: .medium))
                Text(result.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(result.groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    ForEach(group.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Text(row.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(rowTint(row.state))
                            if let note = row.note {
                                Text(note)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private var iconName: String {
        switch result.state {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch result.state {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        case .unknown: return .gray
        }
    }

    private func rowTint(_ state: ProbeState?) -> Color {
        guard let state else { return .primary }
        switch state {
        case .ok: return .primary
        case .warning: return .orange
        case .failed: return .red
        case .unknown: return .secondary
        }
    }
}

/// 元数据行
struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}
