import SwiftUI

/// 内联日志视图 - 性能优化版
/// - filteredLines 改 @State 缓存（避免每次 render 重算）
/// - scrollTo 去掉 withAnimation（避免每行触发 layout pass）
/// - Pause 用 LogWatcher.isPaused（保留历史）
/// - Clear 用 clear(source:)（只清当前服务）
struct InlineLogView: View {
    let serviceType: ServiceType
    let isFullscreen: Bool
    let onEnterFullscreen: () -> Void
    let onExitFullscreen: () -> Void

    @EnvironmentObject var appState: AppState
    // 直接观察 logWatcher，让 lines 变化触发 view 更新
    @ObservedObject private var logWatcher: LogWatcher

    @State private var searchText: String = ""
    @State private var cachedLines: [LogLine] = []  // 性能：缓存避免重复过滤

    /// 注入 logWatcher 的 init（必须显式传入，因为是 private）
    init(serviceType: ServiceType,
         isFullscreen: Bool,
         onEnterFullscreen: @escaping () -> Void,
         onExitFullscreen: @escaping () -> Void,
         logWatcher: LogWatcher) {
        self.serviceType = serviceType
        self.isFullscreen = isFullscreen
        self.onEnterFullscreen = onEnterFullscreen
        self.onExitFullscreen = onExitFullscreen
        self._logWatcher = ObservedObject(initialValue: logWatcher)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
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

                    // 暂停/继续
                    Button {
                        logWatcher.isPaused.toggle()
                    } label: {
                        Image(systemName: logWatcher.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help(logWatcher.isPaused ? "继续接收新日志" : "暂停接收新日志（保留已显示历史）")

                    // 复制
                    Button {
                        let text = cachedLines.map { "\(Self.timeFormatter.string(from: $0.timestamp)) \($0.content)" }.joined(separator: "\n")
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
                        logWatcher.clear(source: currentSource)
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

            Divider().opacity(0.2)

            // 日志内容
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
                    // 性能：去掉 withAnimation（避免每行触发 layout pass）
                    if !logWatcher.isPaused, let last = cachedLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12, style: .continuous)
                .fill(.clear)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: isFullscreen ? 0 : 12))
        )
        .padding(.horizontal, isFullscreen ? 0 : 16)
        .padding(.bottom, isFullscreen ? 0 : 8)
        .onAppear {
            startLogStream()
            refreshCache()
        }
        .onChange(of: serviceType) { _, _ in
            startLogStream()
            refreshCache()
        }
        .onChange(of: searchText) { _, _ in
            refreshCache()
        }
        .onChange(of: logWatcher.lines.count) { _, _ in
            refreshCache()
        }
    }

    /// 当前 service 对应的 LogSource
    private var currentSource: LogSource {
        switch serviceType {
        case .astrbot: return .astrbot
        case .napcat: return .napcat
        case .shipyard: return .shipyard
        }
    }

    /// 启动当前 service 的日志流（不停 watcher，不清空所有日志）
    /// - 切换 service 时 stop 当前 stream，重启新 stream
    /// - 不调用 clear() —— 保留所有 service 的历史日志（包括 pause 的效果）
    private func startLogStream() {
        logWatcher.stop()
        // 注意：不调用 clear()，保留其他 service 的历史
        switch serviceType {
        case .astrbot:
            let path = (AppSettings.shared.astrbotLogPath as NSString).expandingTildeInPath
            logWatcher.watchAstrBotLogFile(path)
        case .napcat:
            let containerName = AppSettings.shared.napcatContainer
            if !containerName.isEmpty {
                logWatcher.startContainerLogStream(containerName: containerName, source: .napcat)
            } else {
                appState.appendLog(level: .warn, source: .napcat, content: "未配置 NapCat 容器")
            }
        case .shipyard:
            let containerName = AppSettings.shared.shipyardContainer
            if !containerName.isEmpty {
                logWatcher.startContainerLogStream(containerName: containerName, source: .shipyard)
            } else {
                appState.appendLog(level: .warn, source: .shipyard, content: "未配置 Shipyard 容器")
            }
        }
    }

    /// 性能：缓存过滤结果
    /// 只在以下情况重算：searchText 变 / logWatcher.lines.count 变 / serviceType 变
    private func refreshCache() {
        let source = currentSource
        let search = searchText
        let all = logWatcher.lines.filter { $0.source == source }
        if search.isEmpty {
            cachedLines = all
        } else {
            cachedLines = all.filter { $0.content.localizedCaseInsensitiveContains(search) }
        }
    }
}

/// 单行日志
struct LogRowView: View {
    let line: LogLine

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
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
