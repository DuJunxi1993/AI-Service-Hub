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
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshContainers()
        for descriptor in settings.orderedServices {
            await refresh(descriptor)
        }
    }

    /// 刷新单个服务
    func refresh(_ descriptor: ServiceDescriptor) async {
        var snapshot = snapshots[descriptor.id] ?? ServiceSnapshot(descriptorID: descriptor.id)

        // 过渡态（启动中 / 停止中）不被轮询覆盖
        if snapshot.status.isTransitional {
            snapshots[descriptor.id] = snapshot
            return
        }

        var probeResults: [ProbeResult] = []
        for probe in descriptor.probes {
            probeResults.append(await evaluator.evaluate(probe))
        }
        snapshot.probeResults = probeResults

        switch descriptor.lifecycle {
        case .observed:
            snapshot = await observedSnapshot(descriptor: descriptor, snapshot: snapshot, probes: probeResults)
        case .managed:
            snapshot = await managedSnapshot(descriptor: descriptor, snapshot: snapshot)
        }

        // WebUI 地址：日志里解析出来的优先
        if let url = await hub.webURL(for: descriptor.id) {
            snapshot.webURL = url
        } else if snapshot.webURL == nil {
            snapshot.webURL = await fallbackWebURL(for: descriptor)
        }

        snapshot.updatedAt = Date()
        snapshots[descriptor.id] = snapshot
    }

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

        setStatus(id, .starting)
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

            await refreshAll()
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
        do {
            switch descriptor.managed {
            case .process:
                if let record = settings.ledgerRecord(for: id) {
                    await processDriver.stop(record: record)
                    settings.removeLedgerRecord(serviceID: id)
                }

            case .container(let spec):
                try await docker.stop(container: spec.containerName)

            case nil:
                break
            }

            await refreshAll()
            NotificationManager.shared.send(title: "服务停止", body: "\(descriptor.name) 已停止")
        } catch {
            fail(id, message: error.localizedDescription)
            NotificationManager.shared.send(title: "停止失败", body: "\(descriptor.name)：\(error.localizedDescription)")
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
        errorMessage = "\(descriptor.name) 没有可用的 Web UI 地址"
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
        errorMessage = message
    }

}
