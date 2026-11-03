import SwiftUI
import AppKit
import AiServiceHubCore

/// 编辑一个已登记的服务
struct EditServiceSheet: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) var dismiss

    @State private var draft: ServiceDescriptor

    init(descriptor: ServiceDescriptor) {
        _draft = State(initialValue: descriptor)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsTextFieldRow(
                        title: "名称",
                        description: "显示在侧边栏里的名字",
                        text: $draft.name,
                        placeholder: "服务名称"
                    )

                    if draft.lifecycle == .managed {
                        autoStartSection
                    }

                    switch draft.managed {
                    case .process(let spec):
                        processSection(spec: spec)
                    case .container(let spec):
                        containerSection(spec: spec)
                    case nil:
                        observedSection
                    }
                }
                .padding(20)
            }
            Divider().opacity(0.2)
            footer
        }
        .frame(width: 560, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: draft.appearance.iconSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("编辑服务")
                    .font(.title3.weight(.semibold))
                Text(modeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("保存") {
                settings.update(draft)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var accent: Color {
        Color(
            red: draft.appearance.accent.red,
            green: draft.appearance.accent.green,
            blue: draft.appearance.accent.blue
        )
    }

    private var modeLabel: String {
        switch draft.lifecycle {
        case .observed: return "纯监控 · 本程序不接管它的进程"
        case .managed:
            switch draft.driver {
            case .process: return "可管理 · 持有子进程"
            case .container: return "可管理 · 委托 Docker 容器"
            case nil: return "可管理"
            }
        }
    }

    private var autoStartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("启动时自动拉起", isOn: $draft.autoStart)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
            Text("本程序启动或重启时，会自动拉起被勾选的服务。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func processSection(spec: ProcessSpec) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .process(let current) = draft.managed {
                SettingsTextFieldRow(
                    title: "可执行文件",
                    description: "程序的绝对路径",
                    text: Binding(
                        get: { current.executable },
                        set: { newValue in
                            var updated = current
                            updated.executable = newValue
                            draft.managed = .process(updated)
                        }
                    ),
                    placeholder: "/usr/local/bin/myapp"
                )

                SettingsTextFieldRow(
                    title: "参数",
                    description: "用空格分隔",
                    text: Binding(
                        get: { current.arguments.joined(separator: " ") },
                        set: { newValue in
                            var updated = current
                            updated.arguments = newValue.split(separator: " ").map(String.init)
                            draft.managed = .process(updated)
                        }
                    ),
                    placeholder: "--port 8080"
                )

                SettingsTextFieldRow(
                    title: "工作目录",
                    description: "留空则继承",
                    text: Binding(
                        get: { current.workingDirectory ?? "" },
                        set: { newValue in
                            var updated = current
                            updated.workingDirectory = newValue.isEmpty ? nil : newValue
                            draft.managed = .process(updated)
                        }
                    ),
                    placeholder: "/Users/me/myapp"
                )

                Toggle("经由 shell 执行", isOn: Binding(
                    get: { current.shellMode },
                    set: { newValue in
                        var updated = current
                        updated.shellMode = newValue
                        draft.managed = .process(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))

                Toggle("daemon 化（脱离本程序独立运行）", isOn: Binding(
                    get: { current.ownership.detached },
                    set: { newValue in
                        var updated = current
                        updated.ownership.detached = newValue
                        draft.managed = .process(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))

                Toggle("本程序退出时终止它", isOn: Binding(
                    get: { current.ownership.stopOnAppQuit },
                    set: { newValue in
                        var updated = current
                        updated.ownership.stopOnAppQuit = newValue
                        draft.managed = .process(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
            }
        }
    }

    @ViewBuilder
    private func containerSection(spec: ContainerSpec) -> some View {
        if case .container(let current) = draft.managed {
            VStack(alignment: .leading, spacing: 14) {
                SettingsTextFieldRow(
                    title: "容器名",
                    description: "本程序会执行 docker start/stop 这个容器",
                    text: Binding(
                        get: { current.containerName },
                        set: { newValue in
                            var updated = current
                            updated.containerName = newValue
                            draft.managed = .container(updated)
                        }
                    ),
                    placeholder: "my-container"
                )

                Toggle("本程序退出时停止该容器", isOn: Binding(
                    get: { current.stopOnAppQuit },
                    set: { newValue in
                        var updated = current
                        updated.stopOnAppQuit = newValue
                        draft.managed = .container(updated)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
            }
        }
    }

    private var observedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这是纯监控服务：本程序只读取它的状态、日志与端口，不会启动或停止它。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("探测项：\(draft.probes.count) 个 · 日志来源：\(draft.logSources.count) 个")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
