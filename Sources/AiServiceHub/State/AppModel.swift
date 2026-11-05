import Foundation
import SwiftUI
import AppKit
import AiServiceHubCore

/// 全局协调器
///
/// 取代旧版的 `AppState`：只负责编排（刷新、启停、自动拉起），
/// 具体能力由 Core 里的驱动与探测器提供，视图只读快照。
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    /// 各服务的运行时快照
    @Published private(set) var snapshots: [UUID: ServiceSnapshot] = [:]

    /// 发现的全部 Docker 容器
    @Published private(set) var allContainers: [DockerContainer] = []

    /// Docker 是否可用
    @Published private(set) var dockerAvailable: Bool = false

    /// 全局错误提示
    @Published var errorMessage: String?

    /// 日志中心
    let hub: LogHub

    private let settings: AppSettings
    private let evaluator = ProbeEvaluator()
    private let processDriver = ProcessDriver()
    private let docker = DockerCLI()
    private let ledger = OwnershipLedger()

    private var pollTimer: Timer?
    private var isRefreshing = false

    /// 过渡态开始时间（用于判断启动/停止是否超时）
    private var transitionStartedAt: [UUID: Date] = [:]

    /// 最近一次枚举的进程表
    ///
    /// 每轮刷新只 `ps` 一次（这台机器有 ~800 个进程），复用给所有探测，
    /// 「停止全部进程」的确认对话框也用它来数匹配到的进程。
    private var processTableCache = ProcessTable(entries: [])

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.hub = LogHub()
        bootstrap()
    }

    // MARK: - 启动

    private func bootstrap() {
        // 为每个服务建立快照与日志来源
        for descriptor in settings.orderedServices {
            snapshots[descriptor.id] = ServiceSnapshot(descriptorID: descriptor.id)
            Task { await hub.attach(descriptor: descriptor) }
        }
        Task {
            // 上次若是被强杀/崩溃，先回收本应随 app 结束的孤儿进程
            let reclaimed = await settings.reclaimOrphanProcesses(using: ledger)
            if !reclaimed.isEmpty {
                AppLog.info("已回收 \(reclaimed.count) 个孤儿进程")
            }
            await refreshAll()
            await autoStartEnabledServices()
        }
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let interval = TimeInterval(max(1, settings.pollingInterval))
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                await self.refreshAll()
            }
        }
    }

    func restartPolling() {
        startPolling()
    }

    // MARK: - 刷新

    /// 刷新全部服务状态
    ///
    /// 轮询用这个版本（并发时直接跳过，避免任务堆积）。
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshAllNow()
    }

    /// 强制刷新全部服务状态
    ///
    /// 启停完成后必须调用：它不受轮询的 `isRefreshing` 守卫限制，
    /// 否则启停刚结束时正好撞上轮询，这次刷新就被丢弃，
    /// 状态会一直停在「启动中」直到下一轮轮询。
    func refreshAllNow() async {
        await refreshContainers()
        // 每轮只枚举一次进程表，供所有探测复用
        let processTable = await ProcessInspector().snapshot()
        processTableCache = processTable
        for descriptor in settings.orderedServices {
            await refresh(descriptor, processTable: processTable)
        }
    }

    /// 刷新单个服务
    func refresh(_ descriptor: ServiceDescriptor, processTable: ProcessTable? = nil) async {
        var snapshot = snapshots[descriptor.id] ?? ServiceSnapshot(descriptorID: descriptor.id)

        // 先记下过渡态：下面的快照计算会覆盖 status
        let pendingTransition = snapshot.status.isTransitional ? snapshot.status : nil
        let transitionStart = transitionStartedAt[descriptor.id]

        var probeResults: [ProbeResult] = []
        for probe in descriptor.probes {
            probeResults.append(await evaluator.evaluate(probe, table: processTable))
        }
        snapshot.probeResults = probeResults

        switch descriptor.lifecycle {
        case .observed:
            snapshot = await observedSnapshot(descriptor: descriptor, snapshot: snapshot, probes: probeResults)
        case .managed:
            snapshot = await managedSnapshot(descriptor: descriptor, snapshot: snapshot)
        }

        // 过渡态结算
        if let pendingTransition, let transitionStart {
            let elapsed = Date().timeIntervalSince(transitionStart)
            switch pendingTransition {
            case .starting:
                if snapshot.status == .running {
                    // 起来了 —— 结束过渡态
                    transitionStartedAt[descriptor.id] = nil
                } else if elapsed > Self.transitionGracePeriod {
                    // 宽限期过了还没起来 —— 判定启动失败
                    snapshot.status = .error
                    snapshot.lastError = "启动超时（等待 \(Int(Self.transitionGracePeriod)) 秒后仍未运行）"
                    transitionStartedAt[descriptor.id] = nil
                } else {
                    // 还在启动途中，保持「启动中」，不要被探测结果覆盖
                    snapshot.status = .starting
                }
            case .stopping:
                if snapshot.status == .stopped {
                    transitionStartedAt[descriptor.id] = nil
                } else if elapsed > Self.transitionGracePeriod {
                    snapshot.status = .error
                    snapshot.lastError = "停止超时（等待 \(Int(Self.transitionGracePeriod)) 秒后仍在运行）"
                    transitionStartedAt[descriptor.id] = nil
                } else {
                    snapshot.status = .stopping
                }
            default:
                transitionStartedAt[descriptor.id] = nil
            }
        }

        // WebUI 地址：日志里解析出来的优先
        if let url = await hub.webURL(for: descriptor.id) {
            snapshot.webURL = url
        } else if snapshot.webURL == nil {
            snapshot.webURL = await fallbackWebURL(for: descriptor)
        }

        // 状态变化时记一条日志，便于排查「指示灯停在某个状态」这类问题
        let previousStatus = snapshots[descriptor.id]?.status
        if previousStatus != snapshot.status {
            AppLog.info("状态更新 \(descriptor.name)：\(previousStatus?.displayName ?? "—") → \(snapshot.status.displayName)")
        }

        snapshot.updatedAt = Date()
        snapshots[descriptor.id] = snapshot
    }

    /// 过渡态宽限期：容器启动可能要十几秒，进程启动通常几秒
    private static let transitionGracePeriod: TimeInterval = 20

    /// 纯监控服务的状态
    private func observedSnapshot(
        descriptor: ServiceDescriptor,
        snapshot: ServiceSnapshot,
        probes: [ProbeResult]
    ) async -> ServiceSnapshot {
        var result = snapshot

        let failed = probes.filter { $0.state == .failed }
        let warning = probes.filter { $0.state == .warning }
        let unknown = probes.filter { $0.state == .unknown }

        if !probes.isEmpty {
            if !failed.isEmpty {
                result.status = .stopped
            } else if !warning.isEmpty {
                result.status = .degraded
            } else if !unknown.isEmpty {
                result.status = .unknown
            } else {
                result.status = .running
            }
        }

        // 进程信息
        let inspector = ProcessInspector()
        for probe in descriptor.probes {
            guard case .processPattern(let pattern) = probe else { continue }
            let processes = await inspector.allProcesses(matching: [pattern])
            if let first = processes.first {
                result.pid = first.pid
                result.processStartTimeToken = first.startTimeToken
                result.listeningPorts = await inspector.listeningPorts(pid: first.pid)
            }
            break
        }

        return result
    }

    /// 可管理服务的状态
    private func managedSnapshot(
        descriptor: ServiceDescriptor,
        snapshot: ServiceSnapshot
    ) async -> ServiceSnapshot {
        var result = snapshot

        switch descriptor.managed {
        case .process(let spec):
            let record = settings.ledgerRecord(for: descriptor.id)
            let status = await processDriver.status(spec: spec, record: record)
            result.pid = status.pid
            result.processStartTimeToken = status.startTimeToken
            result.startedByUs = status.startedByUs
            result.status = status.isRunning ? .running : .stopped
            if status.pid != nil {
                let ports = await ProcessInspector().listeningPorts(pid: status.pid!)
                result.listeningPorts = ports
            }

        case .container(let spec):
            guard dockerAvailable else {
                result.status = .unknown
                result.lastError = "Docker 不可用"
                return result
            }
            guard let container = allContainers.first(where: { $0.name == spec.containerName }) else {
                result.status = .unknown
                result.containerName = spec.containerName
                result.lastError = "容器不存在"
                return result
            }
            result.containerName = container.name
            result.image = container.image
            result.ports = container.ports
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            result.status = container.isRunning ? .running : .stopped
            result.lastError = nil

        case nil:
            result.status = .unknown
        }

        return result
    }

    /// 刷新容器列表
    func refreshContainers() async {
        let available = await docker.isAvailable()
        dockerAvailable = available
        guard available else {
            allContainers = []
            return
        }
        do {
            allContainers = try await docker.listContainers()
        } catch {
            AppLog.warn("获取容器列表失败：\(error.localizedDescription)")
            allContainers = []
        }
    }

    // MARK: - 启停

    /// 启动服务
    func start(_ id: UUID) async {
        guard let descriptor = settings.service(id: id) else { return }
        guard descriptor.lifecycle == .managed else {
            errorMessage = "\(descriptor.name) 是纯监控服务，不能由本程序启动"
            return
        }

        // 已经在运行就不要重复拉起：否则会 spawn 出第二个实例（典型表现是
        // 端口被占用后新进程立刻退出，而状态看起来「启动成功」）
        if snapshots[id]?.status == .running {
            AppLog.info("\(descriptor.name) 已在运行，跳过启动")
            return
        }

        setStatus(id, .starting)
        transitionStartedAt[id] = Date()
        do {
            switch descriptor.managed {
            case .process(let spec):
                let record = try processDriver.start(spec: spec, serviceID: id)
                settings.upsertLedgerRecord(record)

            case .container(let spec):
                try await docker.start(container: spec.containerName)

            case nil:
                break
            }

            await refreshAllNow()
            NotificationManager.shared.send(title: "服务启动", body: "\(descriptor.name) 已启动")
        } catch {
            fail(id, message: error.localizedDescription)
            NotificationManager.shared.send(title: "启动失败", body: "\(descriptor.name)：\(error.localizedDescription)")
        }
    }

    /// 停止服务
    func stop(_ id: UUID) async {
        guard let descriptor = settings.service(id: id) else { return }
        guard descriptor.lifecycle == .managed else {
            errorMessage = "\(descriptor.name) 是纯监控服务，不能由本程序停止"
            return
        }

        setStatus(id, .stopping)
        transitionStartedAt[id] = Date()
        do {
            switch descriptor.managed {
            case .process:
                // 先停掉本程序持有的那个进程（pid + 启动时间双重校验，最精确）
                if let record = settings.ledgerRecord(for: id) {
                    await processDriver.stop(record: record)
                    settings.removeLedgerRecord(serviceID: id)
                }
                // 再把该服务匹配到的**全部**进程停掉。
                //
                // 只停账本里那一个 pid 是不够的：daemon 化的进程在 app 重启后
                // 会从账本里摘除（reclaimOrphans 故意丢弃 detached 条目），
                // 这时按账本停等于什么都不做 —— 服务照跑不误，
                // 用户点「停止」看着就像没反应。
                let patterns = descriptor.stopPatterns
                if !patterns.isEmpty {
                    let terminated = await processDriver.terminateAll(matching: patterns)
                    if !terminated.isEmpty {
                        AppLog.info("\(descriptor.name)：终止了 \(terminated.count) 个匹配进程")
                    }
                }

            case .container(let spec):
                try await docker.stop(container: spec.containerName)

            case nil:
                break
            }

            await refreshAllNow()
            NotificationManager.shared.send(title: "服务停止", body: "\(descriptor.name) 已停止")
        } catch {
            fail(id, message: error.localizedDescription)
            NotificationManager.shared.send(title: "停止失败", body: "\(descriptor.name)：\(error.localizedDescription)")
        }
    }

    /// 停止服务关联的全部进程（给纯监控服务用）
    ///
    /// 纯监控服务没有驱动、没有进程所有权，常规的「停止」按钮不适用。
    /// 但用户可能想一键停掉它 —— 例如 Hermes 网关、DSH Web。
    /// 这里按服务自己声明的进程匹配模式终止对应进程。
    func stopAllProcesses(of id: UUID) async {
        guard let descriptor = settings.service(id: id) else { return }
        // 用「停止专用」模式：比探测模式全面（Hermes 的进程散落在多处）
        let patterns = descriptor.stopPatterns
        guard !patterns.isEmpty else {
            errorMessage = "\(descriptor.name) 没有配置进程匹配规则，无法停止"
            return
        }

        setStatus(id, .stopping)
        let terminated = await processDriver.terminateAll(matching: patterns)
        await refreshAllNow()

        if terminated.isEmpty {
            AppLog.info("\(descriptor.name)：没有找到运行中的相关进程")
        } else {
            NotificationManager.shared.send(
                title: "服务已停止",
                body: "\(descriptor.name)：已终止 \(terminated.count) 个进程"
            )
        }
    }

    /// 当前匹配该服务停止规则的进程数量（用于确认对话框）
    func matchingProcessCount(for id: UUID) -> Int {
        guard let descriptor = settings.service(id: id) else { return 0 }
        let patterns = descriptor.stopPatterns
        guard !patterns.isEmpty else { return 0 }
        return processTableCache.matching(patterns).count
    }

    /// 打开服务的数据目录
    ///
    /// 优先用服务自己声明的数据目录；没有就退回主目录。
    func openDataDirectory(of id: UUID) {
        guard let descriptor = settings.service(id: id) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
            return
        }
        let path = descriptor.dataDirectory?.isEmpty == false
            ? descriptor.dataDirectory!
            : NSHomeDirectory()
        let url = URL(fileURLWithPath: path)
        // 目录不存在时退回报打开，避免静默失败
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    /// 重启服务
    func restart(_ id: UUID) async {
        await stop(id)
        await start(id)
    }

    /// 启动全部可管理服务
    func startAll() async {
        for descriptor in settings.orderedServices where descriptor.lifecycle == .managed {
            await start(descriptor.id)
        }
    }

    /// 停止全部可管理服务
    func stopAll() async {
        for descriptor in settings.orderedServices.reversed() where descriptor.lifecycle == .managed {
            await stop(descriptor.id)
        }
    }

    /// 启动时自动拉起被勾选的服务
    func autoStartEnabledServices() async {
        let targets = settings.autoStartServices
        guard !targets.isEmpty else { return }
        AppLog.info("自动拉起 \(targets.count) 个服务：\(targets.map(\.name).joined(separator: ", "))")
        for descriptor in targets {
            await start(descriptor.id)
        }
        NotificationManager.shared.send(
            title: "服务已自动启动",
            body: "\(runningCount) / \(settings.services.count) 个服务运行中"
        )
    }

    /// 勾选「启动时自动拉起」时，把没在跑的服务**现在**就拉起来
    ///
    /// 自动拉起原本只在 app 启动时跑一次。于是用户在 app 运行期间勾选这个框，
    /// 看上去毫无反应 —— 而服务可能刚好崩了正等着被拉起。
    /// 勾选即生效：没在跑就现在启动。
    func startIfStopped(_ id: UUID) async {
        guard let descriptor = settings.service(id: id) else { return }
        guard descriptor.lifecycle == .managed else { return }
        // 已经在跑 / 正在切换就不要动
        let status = snapshots[id]?.status ?? .unknown
        guard status != .running, !status.isTransitional else { return }

        AppLog.info("勾选了自动拉起，拉起未运行的服务：\(descriptor.name)")
        await start(id)
    }

    /// 打开总开关时，拉起所有勾选了自动拉起且当前未运行的服务
    func startAutoStartServices() async {
        let targets = settings.autoStartServices
        guard !targets.isEmpty else { return }
        // 先刷新一次拿到准确状态，避免对着已经停掉的服务重复拉起
        await refreshAllNow()
        var started: [String] = []
        for descriptor in targets {
            let status = snapshots[descriptor.id]?.status ?? .unknown
            guard status != .running, !status.isTransitional else { continue }
            await start(descriptor.id)
            started.append(descriptor.name)
        }
        guard !started.isEmpty else { return }
        AppLog.info("打开总开关，拉起：\(started.joined(separator: ", "))")
        NotificationManager.shared.send(
            title: "服务已拉起",
            body: started.joined(separator: "、")
        )
    }

    // MARK: - WebUI

    /// 打开服务的 WebUI
    func openWebUI(_ id: UUID) {
        guard let descriptor = settings.service(id: id) else { return }
        if let url = snapshots[id]?.webURL {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = descriptor.openURL {
            NSWorkspace.shared.open(url)
            return
        }
        errorMessage = "\(descriptor.name)：还没有解析到 WebUI 地址。\n\(webUIReason(descriptor))"
    }

    /// 说明为什么没有 WebUI 地址
    private func webUIReason(_ descriptor: ServiceDescriptor) -> String {
        guard !descriptor.logSources.isEmpty else {
            return "该服务没有配置日志来源，无法从日志中解析地址。"
        }
        guard descriptor.logSources.contains(where: { $0.webUIKind != nil }) else {
            return "该服务的日志没有配置 WebUI 地址提取规则。"
        }
        return "正在从日志中解析，请确认服务已启动并在日志里打印了地址。"
    }

    /// 兜底的 WebUI 地址
    private func fallbackWebURL(for descriptor: ServiceDescriptor) async -> URL? {
        if let url = await hub.webURL(for: descriptor.id) {
            return url
        }
        return descriptor.openURL
    }

    // MARK: - 统计

    /// 运行中的服务数
    var runningCount: Int {
        snapshots.values.filter { $0.status == .running }.count
    }

    /// 服务总数
    var totalCount: Int {
        settings.services.count
    }

    // MARK: - 退出

    /// 退出时清理
    ///
    /// - daemon 化的进程不在此终止（它们本就该继续存活）
    /// - 容器按各自配置决定是否停止
    func cleanupOnExit() async {
        for descriptor in settings.orderedServices {
            guard descriptor.lifecycle == .managed else { continue }
            switch descriptor.managed {
            case .process:
                // detached 的进程继续存活；非 detached 的随 app 结束
                if let record = settings.ledgerRecord(for: descriptor.id),
                   !record.detached {
                    await processDriver.stop(record: record)
                }
            case .container(let spec):
                if spec.stopOnAppQuit {
                    try? await docker.stop(container: spec.containerName)
                }
            case nil:
                break
            }
        }
    }

    // MARK: - 内部

    private func setStatus(_ id: UUID, _ status: ServiceStatus) {
        var snapshot = snapshots[id] ?? ServiceSnapshot(descriptorID: id)
        snapshot.status = status
        snapshots[id] = snapshot
    }

    private func fail(_ id: UUID, message: String) {
        var snapshot = snapshots[id] ?? ServiceSnapshot(descriptorID: id)
        snapshot.status = .error
        snapshot.lastError = message
        snapshots[id] = snapshot
        transitionStartedAt[id] = nil
        errorMessage = message
    }

}
