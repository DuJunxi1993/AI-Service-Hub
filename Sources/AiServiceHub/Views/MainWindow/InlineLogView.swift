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
    /// 是否为横向展开形态（false = 右侧竖直面板）
    let isExpanded: Bool
    /// 在「竖直面板」与「横向铺满」之间切换
    let onToggleExpanded: () -> Void

    @EnvironmentObject var appModel: AppModel

    @State private var searchText: String = ""
    @State private var allLines: [LogLine] = []
    @State private var cachedLines: [LogLine] = []
    @State private var isPaused: Bool = false
    /// 是否自动跟随到最新一行
    @State private var followsTail: Bool = true
    /// 滚动位置（绑定到最新一行的 id）
    @State private var scrollPosition: LogLine.ID?
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
        // 面板本身不再用 Liquid Glass —— 底部那层玻璃装饰会盖住日志内容。
        // 玻璃效果只保留在按钮上（搜索框、暂停、复制、清空、展开）。
        .padding(.horizontal, isExpanded ? 0 : 12)
        .padding(.bottom, isExpanded ? 0 : 4)
        .padding(.top, isExpanded ? 6 : 4)
        .onAppear { syncSubscription(visible: appModel.isMainWindowVisible) }
        .onDisappear { cancelSubscription() }
        .onChange(of: appModel.isMainWindowVisible) { _, visible in
            syncSubscription(visible: visible)
        }
        .onChange(of: descriptor.id) { _, _ in
            syncSubscription(visible: appModel.isMainWindowVisible)
        }
        .onChange(of: searchText) { _, _ in
            applyFilter()
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("实时日志")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                if !searchText.isEmpty {
                    Text("(\(cachedLines.count) 条)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                // 搜索
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    TextField("搜索", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: isExpanded ? 120 : 70)
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

                // 跟随最新 / 停在当前位置
                Button {
                    followsTail.toggle()
                    if followsTail {
                        // 重新开启时立刻回到最新一行
                        followsTail = true
                    }
                } label: {
                    Image(systemName: followsTail ? "arrow.down.to.line" : "arrow.down.to.line.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(followsTail ? "正在跟随最新日志（点击停在当前位置）" : "已停在当前位置（点击恢复跟随最新）")

                // 展开：竖直面板 <-> 横向铺满
                Button {
                    onToggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(isExpanded ? "收回到右侧竖直面板" : "展开为横向面板")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 内容

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if cachedLines.isEmpty {
                    EmptyLogView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(cachedLines) { line in
                        LogRowView(line: line, compact: !isExpanded)
                            .id(line.id)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        // 用**声明式**的滚动位置绑定，而不是 ScrollViewReader.scrollTo。
        //
        // scrollTo 是命令式的跳转：目标行在 LazyVStack 里还没被实例化，
        // SwiftUI 只能滚到**估算**位置 —— 结果就是滚动条停在中间而不是底部；
        // 而且每次跳转都带动画，新行不断到来时动画被反复打断，表现为整屏闪烁。
        //
        // scrollPosition 是绑定：SwiftUI 负责把位置维持在那一行上，
        // 内容增长时会自己跟上，既不闪也不会落到中间。
        .scrollPosition(id: $scrollPosition, anchor: .bottom)
        // 跟随最新：监听**最后一行**而不是行数 ——
        // 缓冲区满了（2000 行）之后行数不再变化，
        // 监听 count 就再也收不到通知了，日志会停在原地不跟随。
        .onChange(of: cachedLines.last?.id) { _, _ in
            scrollToBottom()
        }
        .onAppear {
            scrollToBottom()
        }
    }

    /// 滚动到底部
    private func scrollToBottom() {
        guard followsTail, !isPaused else { return }
        scrollPosition = cachedLines.last?.id
    }

    // MARK: - 订阅

    private func subscribe() {
        cancelSubscription()
        streamTask = Task {
            // 只订阅即可：跟随器是**按订阅创建的**，
            // 它的首次轮询会把历史也顺着这条流推下来。
            // （面板一关，订阅结束 → 跟随停止 → 后台不再轮询日志文件）
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

    /// 按窗口显隐启停跟随
    ///
    /// 视图在窗口收起时**不会销毁**（`onDisappear` 不触发），
    /// 所以要靠 `isMainWindowVisible` 判断用户是不是还在看面板。
    private func syncSubscription(visible: Bool) {
        if visible {
            subscribe()
        } else {
            cancelSubscription()
            allLines = []
            cachedLines = []
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
    /// 窄栏模式：省略日期，只留时分秒
    var compact: Bool = false

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text((compact ? Self.shortFormatter : Self.fullFormatter).string(from: line.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: compact ? 58 : 110, alignment: .leading)

            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textColor)
                // 行高封顶：采集侧已把单行截到 2000 字符，但窄栏里仍会折成
                // 三十多行，一行就能把面板占满、后续日志全被顶出视口。
                .lineLimit(8)
                .truncationMode(.tail)
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
