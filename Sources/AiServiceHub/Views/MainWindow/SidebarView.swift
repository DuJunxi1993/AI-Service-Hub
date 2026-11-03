import SwiftUI
import AiServiceHubCore

/// 侧边栏 - 系统默认 Liquid Glass，支持拖动排序
struct SidebarView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        List(selection: $settings.selectedServiceID) {
            Section {
                ForEach(settings.orderedServices) { descriptor in
                    SidebarItemView(
                        descriptor: descriptor,
                        snapshot: appModel.snapshots[descriptor.id]
                    )
                    .tag(descriptor.id)
                }
                .onMove { from, to in
                    settings.moveServices(from: from, to: to)
                }
            } header: {
                Text("服务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .listStyle(.sidebar)
    }
}

/// 单个侧边栏项
struct SidebarItemView: View {
    let descriptor: ServiceDescriptor
    let snapshot: ServiceSnapshot?

    var body: some View {
        HStack(spacing: 10) {
            // 服务图标
            Image(systemName: descriptor.appearance.iconSymbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 24)

            // 名称 + 副信息
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Text(subtitleText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 生命周期徽章：纯监控 / 可管理
            if descriptor.lifecycle == .observed {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("纯监控：本程序不接管这个服务的进程")
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    private var accentColor: Color {
        Color(
            red: descriptor.appearance.accent.red,
            green: descriptor.appearance.accent.green,
            blue: descriptor.appearance.accent.blue
        )
    }

    private var subtitleText: String {
        switch descriptor.lifecycle {
        case .observed:
            return snapshot?.status.displayName ?? "未探测"
        case .managed:
            switch descriptor.managed {
            case .process:
                if let pid = snapshot?.pid {
                    return "PID: \(pid)"
                }
                return snapshot?.status.displayName ?? "未探测"
            case .container(let spec):
                return spec.containerName
            case nil:
                return "未配置"
            }
        }
    }
}
