import SwiftUI

/// 主窗口 - NavigationSplitView 容器
struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var selectedService: ServiceType?
    @Binding var showSettings: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedService)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            detailContent
        }
        .navigationTitle("AI Service Hub")
        .toolbar {
            // 启停切换（左侧）
            ToolbarItem(placement: .navigation) {
                Button {
                    Task {
                        if appState.runningCount > 0 {
                            await appState.stopAll()
                        } else {
                            await appState.startAll()
                        }
                    }
                } label: {
                    Label(
                        appState.runningCount > 0 ? "停止" : "启动",
                        systemImage: appState.runningCount > 0 ? "stop.fill" : "play.fill"
                    )
                    .foregroundStyle(appState.runningCount > 0 ? Theme.stopColor : Theme.startColor)
                }
                .help(appState.runningCount > 0 ? "停止全部服务" : "启动全部服务")
                .disabled(appState.services.values.contains { $0.status == .starting || $0.status == .stopping })
            }

            // 刷新
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await appState.refreshContainerList()
                        await appState.refreshAllStatuses()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("立即刷新所有服务状态")
            }

            // WebUI
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let type: ServiceType = selectedService ?? settings.selectedService
                    appState.openWebUI(type)
                } label: {
                    Label("WebUI", systemImage: "globe")
                }
                .help("打开当前服务的 WebUI")
            }

            // 数据目录
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.openDataDirectory()
                } label: {
                    Label("数据目录", systemImage: "folder")
                }
                .help("在 Finder 中打开数据目录")
            }

            // 设置（最右侧）
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .help("打开设置")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(settings)
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
            // 菜单栏点击：先唤起 app，再用 openWindow 显示持久窗口
            // （Window(id:) 关闭后 NSWindow 仍存活，openWindow 重新显示）
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .onChange(of: selectedService) { _, newValue in
            if let newValue {
                settings.selectedService = newValue
            }
        }
        .onAppear {
            if selectedService == nil {
                selectedService = settings.selectedService
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        let type: ServiceType? = selectedService ?? settings.selectedService
        if let type, let service = appState.services[type] {
            ServiceDetailView(
                serviceType: type,
                service: service
            )
        } else {
            EmptyDetailView()
        }
    }
}

/// 未选择任何服务时的占位
struct EmptyDetailView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("从侧边栏选择服务")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(appState.runningCount) / \(appState.totalCount) 运行中")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
