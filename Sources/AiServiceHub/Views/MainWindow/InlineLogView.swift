import SwiftUI
import AiServiceHubCore

/// 内联日志视图
///
/// 日志由 `LogHub` 常驻采集，本视图只是它的一个订阅者：
/// - 切换服务不会中断其他服务的采集
/// - 反复切换不会重复拉取历史（历史只读一次并缓存）
/// - 暂停是视图级的，不会影响其他视图
struct InlineLogView: View {
    let descriptor: ServiceDescriptor
    let isFullscreen: Bool
    let onEnterFullscreen: () -> Void
    let onExitFullscreen: () -> Void

    @EnvironmentObject var appModel: AppModel

    @State private var searchText: String = ""
    @State private var allLines: [LogLine] = []
    @State private var cachedLines: [LogLine] = []
    @State private var isPaused: Bool = false
    @State private var streamTask: Task<Void, Never>?

    private static let bufferLimit = 2000

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.2)
            content
        }
        .background(
            RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12, style: .continuous)
                .fill(.clear)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12))
        )
        .padding(.horizontal, isFullscreen ? 0 : 16)
        .padding(.bottom, isFullscreen ? 0 : 8)
        .onAppear { subscribe() }
        .onDisappear { cancelSubscription() }
        .onChange(of: descriptor.id) { _, _ in
            subscribe()
        }
        .onChange(of: searchText) { _, _ in
            applyFilter()
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("实时日志")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if !searchText.isEmpty {
                Text("(\(cachedLines.count) 条)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 4) {
                // 搜索
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    TextField("搜索", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 100)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular, in: Capsule(style: .continuous))
                )

                // 暂停 / 继续
                Button {
                    togglePause()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(isPaused ? "继续接收新日志" : "暂停接收新日志（保留已显示历史）")

                // 复制
                Button {
                    let text = cachedLines
                        .map { "\(Self.timeFormatter.string(from: $0.timestamp)) \($0.content)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("复制全部过滤结果")

                // 清空（只清当前服务）
                Button {
                    Task {
                        await appModel.hub.removeService(serviceID: descriptor.id)
                        allLines = []
                        applyFilter()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("清空此服务的日志（不影响其他服务）")

                // 全屏
                Button {
                    if isFullscreen {
                        onExitFullscreen()
                    } else {
                        onEnterFullscreen()
                    }
                } label: {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 内容

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if cachedLines.isEmpty {
                        EmptyLogView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        ForEach(cachedLines) { line in
                            LogRowView(line: line)
                                .id(line.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: cachedLines.count) { _, _ in
                if !isPaused, let last = cachedLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - 订阅

    private func subscribe() {
        cancelSubscription()
        streamTask = Task {
            // 先取一次历史（Hub 里已经缓存，不会重复）
            let history = await appModel.hub.history(serviceID: descriptor.id)
            await MainActor.run {
                allLines = history
                applyFilter()
            }
            // 再持续接收
            for await batch in await appModel.hub.subscribe(serviceID: descriptor.id) {
                await MainActor.run {
                    guard !isPaused else { return }
                    allLines.append(contentsOf: batch)
                    if allLines.count > Self.bufferLimit {
                        allLines.removeFirst(allLines.count - Self.bufferLimit)
                    }
                    applyFilter()
                }
            }
        }
    }

    private func cancelSubscription() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func togglePause() {
        isPaused.toggle()
        if !isPaused {
            // 恢复时把暂停期间 hub 继续采集到的内容补回来
            Task {
                let history = await appModel.hub.history(serviceID: descriptor.id)
                await MainActor.run {
                    allLines = history
                    applyFilter()
                }
            }
        }
    }

    private func applyFilter() {
        if searchText.isEmpty {
            cachedLines = allLines
        } else {
            cachedLines = allLines.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }
}

/// 单行日志
struct LogRowView: View {
    let line: LogLine

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: line.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 110, alignment: .leading)

            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(nil)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(
            line.level == .error ? Color.red.opacity(0.08) :
            line.level == .warn ? Color.orange.opacity(0.06) :
            Color.clear
        )
    }

    private var textColor: Color {
        switch line.level {
        case .error: return Color(red: 0.90, green: 0.25, blue: 0.25)
        case .warn: return Color(red: 0.80, green: 0.55, blue: 0.10)
        case .info: return .primary
        case .debug: return Color(white: 0.5)
        }
    }
}

/// 空日志状态
struct EmptyLogView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("暂无日志")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
