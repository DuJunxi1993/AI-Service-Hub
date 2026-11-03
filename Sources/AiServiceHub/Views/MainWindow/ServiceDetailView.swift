import SwiftUI
import AiServiceHubCore

/// 服务详情视图 - 玻璃头部 + 操作按钮 + 内联日志
struct ServiceDetailView: View {
    let descriptor: ServiceDescriptor

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var isLogFullscreen: Bool = false

    private var snapshot: ServiceSnapshot {
        appModel.snapshots[descriptor.id] ?? ServiceSnapshot(descriptorID: descriptor.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerCard

            Divider()
                .opacity(0.2)
                .padding(.vertical, 8)

            if isLogFullscreen {
                InlineLogView(
                    descriptor: descriptor,
                    isFullscreen: true,
                    onEnterFullscreen: {},
                    onExitFullscreen: { withAnimation(Theme.springAnimation) { isLogFullscreen = false } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    metadataSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .opacity(0.2)

                    InlineLogView(
                        descriptor: descriptor,
                        isFullscreen: false,
                        onEnterFullscreen: { withAnimation(Theme.springAnimation) { isLogFullscreen = true } },
                        onExitFullscreen: {}
                    )
                    .frame(maxHeight: .infinity)
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

    // MARK: - 元数据

    private var metadataSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadataRows

                if !snapshot.probeResults.isEmpty {
                    Divider().opacity(0.3)
                    probeSection
                }

                actionButtons
            }
            .padding(20)
        }
    }

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
        HStack(spacing: 12) {
            Spacer()

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

                Button(role: .destructive) {
                    Task { await appModel.stop(descriptor.id) }
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.stopColor)
                .disabled(!snapshot.status.canStop)
                .controlSize(.large)

                Button {
                    Task { await appModel.restart(descriptor.id) }
                } label: {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(snapshot.status == .stopped || snapshot.status == .unknown)
                .controlSize(.large)
            }

            Button {
                appModel.openWebUI(descriptor.id)
            } label: {
                Label("打开 WebUI", systemImage: "safari")
            }
            .buttonStyle(.glassProminent)
            .disabled(snapshot.webURL == nil)
            .controlSize(.large)
            .help(snapshot.webURL?.absoluteString ?? "没有可用的 WebUI 地址")

            Spacer()
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
