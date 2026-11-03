import SwiftUI

/// 侧边栏 - 系统默认 Liquid Glass，支持拖动排序
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @Binding var selection: ServiceType?

    var body: some View {
        List(selection: $selection) {
            Section {
                // 按 settings.serviceOrder 顺序渲染（支持用户拖动）
                ForEach(settings.serviceOrder, id: \.self) { type in
                    if let service = appState.services[type] {
                        SidebarItemView(serviceType: type, service: service)
                            .tag(type)
                    }
                }
                .onMove { from, to in
                    settings.serviceOrder.move(fromOffsets: from, toOffset: to)
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
    let serviceType: ServiceType
    let service: Service

    var body: some View {
        HStack(spacing: 10) {
            // 服务图标
            Image(systemName: serviceType.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(serviceType.accentColor)
                .frame(width: 24)

            // 名称 + 副信息
            VStack(alignment: .leading, spacing: 1) {
                Text(serviceType.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Text(subtitleText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    private var subtitleText: String {
        if serviceType == .astrbot {
            if let pid = service.pid {
                return "PID: \(pid)"
            }
            return serviceType.subtitle
        } else {
            if let container = service.containerName {
                return container
            }
            if service.status == .unknown {
                return "未配置"
            }
            return serviceType.subtitle
        }
    }
}
