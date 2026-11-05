import SwiftUI
import AppKit
import AiServiceHubCore

/// 设置面板 - 以 sheet 形式从主窗口弹出
///
/// 布局原则：
/// - 标签在输入框上方
/// - 每节顶部有图标 + 标题 + 简介
/// - 状态信息直接显示在相关设置旁
struct SettingsSheet: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) var dismiss

    @State private var showAddWizard = false
    @State private var editingService: ServiceDescriptor?
    @State private var showRemoveConfirm: ServiceDescriptor?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            content
        }
        .frame(width: 620, height: 720)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showAddWizard) {
            AddServiceWizard()
                .environmentObject(settings)
                .environmentObject(appModel)
        }
        .sheet(item: $editingService) { descriptor in
            EditServiceSheet(descriptor: descriptor)
                .environmentObject(settings)
                .environmentObject(appModel)
        }
        .alert("移除服务", isPresented: Binding(
            get: { showRemoveConfirm != nil },
            set: { if !$0 { showRemoveConfirm = nil } }
        ), presenting: showRemoveConfirm) { descriptor in
            Button("移除", role: .destructive) {
                Task {
                    await appModel.hub.removeService(serviceID: descriptor.id)
                    settings.remove(id: descriptor.id)
                    showRemoveConfirm = nil
                }
            }
            Button("取消", role: .cancel) {
                showRemoveConfirm = nil
            }
        } message: { descriptor in
            Text("将从列表中移除「\(descriptor.name)」。不会影响它本身的运行。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.title3.weight(.semibold))
                Text("AI Service Hub 配置")
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
                if let notice = settings.migrationNotice {
                    migrationBanner(notice)
                }
                generalSection
                servicesSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private func migrationBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                Text("旧版配置已转换为新的服务描述符；AstrBot 保持「持有子进程」，NapCat / Shipyard 转为「委托容器」。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                settings.migrationNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
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
                        appModel.restartPolling()
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
                    title: "服务状态通知",
                    description: "服务启停时显示系统通知",
                    isOn: $settings.enableNotifications
                )
            }
        }
    }

    // MARK: - 服务管理

    private var servicesSection: some View {
        SettingsCard(title: "服务", icon: "square.grid.2x2.fill", tint: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    title: "启动时自动拉起服务",
                    description: "总开关；具体拉起哪些服务在下方逐项勾选",
                    isOn: Binding(
                        get: { settings.autoStartAllServices },
                        set: { newValue in
                            settings.autoStartAllServices = newValue
                            // 打开总开关就把勾选了的、当前没在跑的服务拉起来
                            if newValue {
                                Task { await appModel.startAutoStartServices() }
                            }
                        }
                    )
                )

                Divider().opacity(0.3)

                VStack(spacing: 8) {
                    ForEach(settings.orderedServices) { descriptor in
                        ServiceManagementRow(
                            descriptor: descriptor,
                            autoStartEnabled: $settings.autoStartAllServices,
                            onToggleAutoStart: { newValue in
                                var updated = descriptor
                                updated.autoStart = newValue
                                settings.update(updated)
                                // 勾选即生效：自动拉起只在 app 启动时跑一次，
                                // 在运行中勾选却什么都不发生会让人以为坏了
                                if updated.shouldStartImmediately(comparedTo: descriptor) {
                                    Task { await appModel.startIfStopped(updated.id) }
                                }
                            },
                            status: appModel.snapshots[descriptor.id]?.status,
                            onEdit: { editingService = descriptor },
                            onRemove: { showRemoveConfirm = descriptor }
                        )
                    }
                }

                HStack {
                    Button {
                        showAddWizard = true
                    } label: {
                        Label("添加服务", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        settings.restoreBuiltinPresets()
                    } label: {
                        Label("恢复内置预设", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        Task { await appModel.refreshContainers() }
                    } label: {
                        Label("刷新容器列表", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                    Text("\(Self.versionString) · macOS 26 Tahoe")
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

    /// 版本号从 Info.plist 读取，避免多处硬编码
    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
        return "v\(version)"
    }
}

// MARK: - 服务管理行

struct ServiceManagementRow: View {
    let descriptor: ServiceDescriptor
    @Binding var autoStartEnabled: Bool
    let onToggleAutoStart: (Bool) -> Void
    /// 当前状态（用于显示服务是不是真的跑着）
    var status: ServiceStatus? = nil
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.appearance.iconSymbol)
                .font(.system(size: 13))
                .foregroundStyle(accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.name)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 4) {
                    Text(modeLabel)
                        .font(.system(size: 9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    if descriptor.lifecycle == .managed, descriptor.driver == .container,
                       let container = containerName {
                        Text(container)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                // 运行状态 —— 勾选「自动拉起」后一眼能看出有没有真的跑起来
                if let status, descriptor.lifecycle == .managed {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 5, height: 5)
                        Text(status.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            if descriptor.lifecycle == .managed {
                Toggle("启动时自动拉起", isOn: Binding(
                    get: { descriptor.autoStart },
                    set: onToggleAutoStart
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(!autoStartEnabled)
                .help(autoStartEnabled
                      ? "启动本程序时自动拉起这个服务；勾选时若它没在跑，会立即拉起"
                      : "总开关已关闭")
            } else {
                Text("只读监控")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("本程序不接管这个服务的进程")
            }

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("移除")
        }
        .padding(.vertical, 2)
    }

    private var modeLabel: String {
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

    private var containerName: String? {
        if case .container(let spec) = descriptor.managed {
            return spec.containerName
        }
        return nil
    }

    private var accent: Color {
        Color(
            red: descriptor.appearance.accent.red,
            green: descriptor.appearance.accent.green,
            blue: descriptor.appearance.accent.blue
        )
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
