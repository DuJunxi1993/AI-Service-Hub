import SwiftUI

/// 服务详情视图 - 玻璃头部 + 操作按钮 + 内联日志
struct ServiceDetailView: View {
    let serviceType: ServiceType
    let service: Service

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var isLogFullscreen: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 上：头部信息卡片
            headerCard

            Divider()
                .opacity(0.2)
                .padding(.vertical, 8)

            // 中：详情区（元数据 + 日志），占主要空间
            if isLogFullscreen {
                InlineLogView(
                    serviceType: serviceType,
                    isFullscreen: true,
                    onEnterFullscreen: {},
                    onExitFullscreen: { withAnimation(Theme.springAnimation) { isLogFullscreen = false } },
                    logWatcher: appState.logWatcherRef
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // 上半：元数据
                    metadataSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .opacity(0.2)

                    // 下半：日志（占一半）
                    InlineLogView(
                        serviceType: serviceType,
                        isFullscreen: false,
                        onEnterFullscreen: { withAnimation(Theme.springAnimation) { isLogFullscreen = true } },
                        onExitFullscreen: {},
                        logWatcher: appState.logWatcherRef
                    )
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
                .opacity(0.2)

            // 状态栏（最底）
            StatusBarView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 头部卡片

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            // 服务大图标
            ZStack {
                Circle()
                    .fill(serviceType.accentColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: serviceType.iconName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(serviceType.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(serviceType.displayName)
                        .font(.title2.weight(.semibold))

                    // 状态徽章
                    HStack(spacing: 4) {
                        StatusDot(status: service.status)
                        Text(service.status.displayName)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(statusBadgeColor.opacity(0.15))
                    )
                }

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 状态信息
            if let error = service.lastError, service.status == .error {
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
                .glassEffect(.regular.tint(serviceType.accentColor.opacity(0.08)), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var statusBadgeColor: Color {
        switch service.status {
        case .running: return .green
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }

    private var subtitle: String {
        if let image = service.image {
            return image
        }
        if let container = service.containerName {
            return container
        }
        if let pid = service.pid {
            return "PID: \(pid)"
        }
        return serviceType.subtitle
    }

    // MARK: - 元数据

    private var metadataSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if serviceType == .astrbot {
                    astrBotMetadata
                } else {
                    containerMetadata
                }

                // 操作按钮（额外的大按钮）
                HStack(spacing: 12) {
                    Spacer()
                    Button {
                        Task { await appState.startService(serviceType) }
                    } label: {
                        Label("启动", systemImage: "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.startColor)
                    .disabled(!service.status.canStart)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        Task { await appState.stopService(serviceType) }
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.stopColor)
                    .disabled(!service.status.canStop)
                    .controlSize(.large)

                    Button {
                        Task { await appState.restartService(serviceType) }
                    } label: {
                        Label("重启", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(service.status != .running)
                    .controlSize(.large)

                    Button {
                        appState.openWebUI(serviceType)
                    } label: {
                        Label("打开 WebUI", systemImage: "safari")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(service.webURL == nil)
                    .controlSize(.large)
                    .help(service.webURL?.absoluteString ?? "等待服务启动...")
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    private var astrBotMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetadataRow(label: "进程 PID", value: service.pid.map { String($0) } ?? "—")
            MetadataRow(label: "WebUI 端口", value: "\(settings.astrBotWebPort)")
            MetadataRow(label: "启动模式", value: settings.astrBotLaunchMode.displayName)
            MetadataRow(label: "数据目录", value: settings.dataDirectory)
        }
    }

    private var containerMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetadataRow(label: "容器名", value: service.containerName ?? "—")
            MetadataRow(label: "镜像", value: service.image ?? "—")
            MetadataRow(label: "端口映射", value: service.ports.isEmpty ? "—" : service.ports.joined(separator: ", "))
            MetadataRow(label: "状态", value: service.status.displayName)
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
            Spacer()
        }
    }
}
