import SwiftUI
import AppKit
import AiServiceHubCore

/// 主窗口 - NavigationSplitView 容器
struct MainWindowView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @Binding var showSettings: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 230, max: 340)
        } detail: {
            detailContent
                // 工具栏必须挂在 detail 上：挂在 NavigationSplitView 上会落到
                // **侧栏那一侧**的工具栏区，按钮就贴在左边而不是最右侧。
                .toolbar {
                    // 顺序：刷新 → WebUI → 数据目录 → 设置 → 启停（最右侧）
                    //
                    // 注意：窗口**不能**用 `.windowStyle(.hiddenTitleBar)` ——
                    // 那会让 SwiftUI 把工具栏渲染成贴合内容宽度的悬浮胶囊，
                    // ToolbarItem 的 placement 被忽略，按钮会全贴在左边。
                    // 换成真实标题栏后，`.primaryAction` 才落在窗口最右侧。

                    // 刷新
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await appModel.refreshAll() }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .help("立即刷新所有服务状态")
                    }

                    // WebUI
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let id = currentSelection {
                                appModel.openWebUI(id)
                            }
                        } label: {
                            Label("WebUI", systemImage: "globe")
                        }
                        .help("打开当前服务的 WebUI")
                        .disabled(currentSelection == nil
                                  || appModel.snapshots[currentSelection ?? UUID()]?.webURL == nil)
                    }

                    // 数据目录（当前选中服务的实际数据目录）
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let id = currentSelection {
                                appModel.openDataDirectory(of: id)
                            } else {
                                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
                            }
                        } label: {
                            Label("数据目录", systemImage: "folder")
                        }
                        .help(currentDataDirectoryHint)
                    }

                    // 设置
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape.fill")
                        }
                        .help("打开设置")
                    }

                    // 启停切换（最右侧）
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                if appModel.runningCount > 0 {
                                    await appModel.stopAll()
                                } else {
                                    await appModel.startAll()
                                }
                            }
                        } label: {
                            Label(
                                appModel.runningCount > 0 ? "停止" : "启动",
                                systemImage: appModel.runningCount > 0 ? "stop.fill" : "play.fill"
                            )
                            .foregroundStyle(appModel.runningCount > 0 ? Theme.stopColor : Theme.startColor)
                        }
                        .help(appModel.runningCount > 0 ? "停止全部服务" : "启动全部服务")
                        .disabled(isTransitioning)
                    }
                }
        }
        .navigationTitle("AI Service Hub")
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(settings)
                .environmentObject(appModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
            // 菜单栏点击：先唤起 app，再用 openWindow 显示持久窗口
            // （Window(id:) 关闭后 NSWindow 仍存活，openWindow 重新显示）
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        .onAppear {
            if settings.selectedServiceID == nil {
                settings.selectedServiceID = settings.orderedServices.first?.id
            }
        }
    }

    private var isTransitioning: Bool {
        appModel.snapshots.values.contains { $0.status.isTransitional }
    }

    private var currentSelection: UUID? {
        settings.selectedServiceID ?? settings.orderedServices.first?.id
    }

    @ViewBuilder
    private var detailContent: some View {
        if let id = currentSelection,
           let descriptor = settings.service(id: id) {
            ServiceDetailView(descriptor: descriptor)
        } else {
            EmptyDetailView()
        }
    }

    /// 数据目录按钮的提示文字
    private var currentDataDirectoryHint: String {
        guard let id = currentSelection, let descriptor = settings.service(id: id) else {
            return "在 Finder 中打开主目录"
        }
        if let directory = descriptor.dataDirectory {
            return "在 Finder 中打开 \(directory)"
        }
        return "在 Finder 中打开主目录"
    }
}

/// 未选择任何服务时的占位
struct EmptyDetailView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("从侧边栏选择服务")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(appModel.runningCount) / \(appModel.totalCount) 运行中")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
