import SwiftUI
import AiServiceHubCore

/// 服务详情视图 —— 头部卡片 + 信息区 + **可收起的**日志面板
///
/// 布局：
/// - **常态**：信息区占满整块，日志只是底部一条窄条（点击才展开）
/// - **展开**：信息区在上，日志横向铺满整个下半部分
///
/// 日志面板常态收起有两个好处：
/// - 收起时 `InlineLogView` **根本不会被创建** —— 那棵两千行的
///   `LazyVStack` 不存在，自然也不会有它的布局与重排开销
/// - 没人看日志时不会订阅日志源 → 跟随器不启动 → 后台不轮询文件
struct ServiceDetailView: View {
    let descriptor: ServiceDescriptor

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var settings: AppSettings
    /// 日志面板是否展开（常态收起）
    @State private var isLogExpanded: Bool = false
    /// 「停止全部进程」的二次确认
    @State private var showsStopAllConfirmation: Bool = false

    private var snapshot: ServiceSnapshot {
        appModel.snapshots[descriptor.id] ?? ServiceSnapshot(descriptorID: descriptor.id)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 1   // 让给中间那条分隔线

            VStack(spacing: 0) {
                // 标题：占整行
                headerCard

                Divider()
                    .opacity(0.2)
                    .padding(.vertical, 8)

                // 内容：左详细信息（2 份）/ 右控制按钮（1 份）
                HStack(spacing: 0) {
                    infoPane
                        .frame(width: width * 2 / 3)

                    Divider()
                        .opacity(0.2)

                    controlColumn
                        .frame(width: width / 3)
                }
                .frame(minHeight: 220, maxHeight: .infinity)

                // 日志：默认收起（**不渲染**，那两千行视图树就不存在）；
                // 展开时横向占一整行
                if isLogExpanded {
                    Divider()
                        .opacity(0.2)
                    InlineLogView(
                        descriptor: descriptor,
                        isExpanded: true,
                        onToggleExpanded: { withAnimation(Theme.springAnimation) { isLogExpanded = false } }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 140, maxHeight: .infinity)
                } else {
                    Divider()
                        .opacity(0.2)
                    collapsedLogBar
                }

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

    /// 右栏：控制按钮，纵向排布、左对齐
    ///
    /// 单独一栏 —— 按钮不会被长内容顶走，窗口再矮也看得见。
    private var controlColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(role: .destructive) {
                        Task { await appModel.stop(descriptor.id) }
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.stopColor)
                    .disabled(!snapshot.status.canStop)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Task { await appModel.restart(descriptor.id) }
                    } label: {
                        Label("重启", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(snapshot.status == .stopped || snapshot.status == .unknown)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // 纯监控服务：没有驱动，但用户仍可能想一键停掉它
                    Button(role: .destructive) {
                        showsStopAllConfirmation = true
                    } label: {
                        Label("停止全部进程", systemImage: "xmark.octagon.fill")
                    }
                    .buttonStyle(.glass)
                    .disabled(descriptor.stopPatterns.isEmpty || snapshot.status == .stopped)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(descriptor.stopPatterns.isEmpty
                          ? "该服务没有配置进程匹配规则"
                          : "终止匹配该服务进程规则的全部进程（\(descriptor.stopPatterns.count) 条规则）")
                }

                Button {
                    appModel.openWebUI(descriptor.id)
                } label: {
                    Label("打开 WebUI", systemImage: "safari")
                }
                .buttonStyle(.glass)
                .disabled(snapshot.webURL == nil)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(snapshot.webURL?.absoluteString ?? webUIUnavailableHint)

                if let dataDirectory = descriptor.dataDirectory {
                    Button {
                        appModel.openDataDirectory(of: descriptor.id)
                    } label: {
                        Label("数据目录", systemImage: "folder")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("在 Finder 中打开 \(dataDirectory)")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 收起态的日志条 —— 点一下展开
    ///
    /// 收起时 `InlineLogView` **根本不会被创建**：
    /// 那两千行的 `LazyVStack` 不存在，既没有布局开销，
    /// 也不会订阅日志源（后台不轮询日志文件）。
    private var collapsedLogBar: some View {
        Button {
            withAnimation(Theme.springAnimation) { isLogExpanded = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text("实时日志")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                sourceSummary
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text("点击展开")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("展开实时日志面板")
    }

    /// 收起条上的来源摘要
    private var sourceSummary: some View {
        let labels = descriptor.logSources.map(\.label)
        guard !labels.isEmpty else { return Text("") }
        return Text(labels.joined(separator: " · "))
    }

    /// 终止前的说明
    private var stopAllWarning: String {
        let patterns = descriptor.stopPatterns
        let matched = appModel.matchingProcessCount(for: descriptor.id)
        var text = "将终止匹配以下规则的进程：\n\(patterns.joined(separator: "\n"))"
        text += "\n\n当前匹配到 \(matched) 个进程。此操作不可撤销。"
        if descriptor.presetIdentifier == DSHPreset.identifier {
            text += "\n\n注意：DSH 的 Web 控制台进程也在其中，停止后本程序会失去与它的连接。"
        }
        return text
    }

    /// 信息区：元数据 + 探测结果 + 操作按钮
    ///
    /// 日志收起后这一栏占满整块宽度 —— 内容按单栏铺开，
    /// 不再留一条限宽的窄列 + 右边一大片空白。
    private var infoPane: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 400

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataRows

                    if !snapshot.probeResults.isEmpty {
                        Divider().opacity(0.3)
                        probeSection
                    }

                    if snapshot.webURL == nil, descriptor.lifecycle == .managed {
                        webUIPendingHint
                    }
                }
                .padding(20)
                // 内容不能反过来撑大容器 —— 否则会溢出被裁
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .environment(\.isNarrowLayout, narrow)
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

    // MARK: - 头部卡片

    /// 标题卡片 —— 占**整行**
    ///
    /// 只有标题（图标 + 名称 + 状态 + 副标题）。
    /// 控制按钮在下面的右栏，不挤在标题里 ——
    /// 那样标题会被压缩，长服务名显示不全。
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

            Spacer(minLength: 12)

            if let error = snapshot.lastError, snapshot.status == .error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 300, alignment: .trailing)
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
}

/// 探测结果卡片
struct ProbeResultView: View {
    let result: ProbeResult

    @Environment(\.isNarrowLayout) private var isNarrow

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
                        if isNarrow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(row.value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(rowTint(row.state))
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let note = row.note {
                                        Text(note)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        } else {
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
                                Spacer(minLength: 0)
                            }
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

    /// 窄面板：标签在上、值在下，值可以换行
    @Environment(\.isNarrowLayout) private var isNarrow

    var body: some View {
        if isNarrow {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    // 最多 3 行 —— 再长就截断，避免一条超长内容把面板撑开
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
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
                Spacer(minLength: 0)
            }
        }
    }
}
