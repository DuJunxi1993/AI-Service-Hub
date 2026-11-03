import Foundation
import SwiftUI
import Combine
import AppKit

/// 全局应用状态（协调所有服务）
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 所有服务（按类型索引）
    @Published var services: [ServiceType: Service] = [:]

    /// 所有已发现的容器
    @Published var allContainers: [ContainerController.Container] = []

    /// 错误提示
    @Published var lastError: String?

    /// 全局启动标记
    private var startedByUs: Set<ServiceType> = []

    private var webUIObserver: NSObjectProtocol?

    /// 轮询定时器
    private var pollTimer: Timer?

    private let astrBotController = AstrBotController()

    /// 暴露给 UI 访问的 AstrBotController
    var strBotController: AstrBotController { astrBotController }
    private let logWatcher = LogWatcher()

    private init() {
        // 初始化服务
        for type in ServiceType.allCases {
            services[type] = Service(type: type)
        }
        // 注册 WebUI URL 监听
        setupWebUIListener()
        // 初始加载 + 启动时自动运行全部服务
        Task {
            await initialSetup()
            if AppSettings.shared.autoStartAllServices {
                AppLog.info("启动时自动运行全部服务")
                await startAll()
                let count = runningCount
                NotificationManager.shared.send(
                    title: "服务已自动启动",
                    body: "\(count) / \(totalCount) 个服务运行中"
                )
            }
        }
    }

    // 缓存：避免每次 refreshStatus 都调 docker inspect
    private var composePathCache: [String: String] = [:]  // [containerName: composePath]
    private var composePortCache: [String: [ServicePortInfo]] = [:]  // [composePath|serviceName: ports] 

    /// 缓存版本：只查一次 docker inspect
    private func cachedComposePath(forContainer containerName: String) -> String? {
        if let cached = composePathCache[containerName] {
            return cached
        }
        if let path = findComposePath(forContainer: containerName) {
            composePathCache[containerName] = path
            return path
        }
        return nil
    }

    private func setupWebUIListener() {
        webUIObserver = NotificationCenter.default.addObserver(
            forName: .webUIDetected,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let source = note.userInfo?["source"] as? LogSource,
                  let url = note.userInfo?["url"] as? URL else { return }
            MainActor.assumeIsolated {
                self?.handleWebUIDetected(source: source, url: url)
            }
        }
    }

    private func handleWebUIDetected(source: LogSource, url: URL) {
        let type = source.serviceType
        guard var svc = services[type] else { return }
        // 替换（token 变/端口变都自动用最新的）
        svc.webURL = url
        services[type] = svc
        AppLog.info("WebUI detected: \(type.displayName) -> \(url.absoluteString)")
    }

    var logWatcherRef: LogWatcher { logWatcher }

    // MARK: - 初始化

    private func initialSetup() async {
        await refreshContainerList()
        await autoMatchContainers()
        await refreshAllStatuses()
        startPolling()
    }

    /// 从 `docker ps -a` 刷新容器列表，并按 image 关键字自动匹配
    func refreshContainerList() async {
        guard ContainerController.isDockerAvailable() else {
            AppLog.warn("Docker 不可用")
            allContainers = []
            return
        }
        do {
            let containers = try await ContainerController.listAll()
            self.allContainers = containers
        } catch {
            AppLog.warn("Failed to list containers: \(error.localizedDescription)")
            allContainers = []
        }
    }

    /// 根据镜像名自动匹配容器到服务
    private func autoMatchContainers() async {
        let settings = AppSettings.shared

        for type in [ServiceType.napcat, .shipyard] {
            let currentName = containerName(for: type)
            // 如果已经设置过且存在，跳过
            if !currentName.isEmpty,
               allContainers.contains(where: { $0.name == currentName }) {
                continue
            }
            // 否则尝试自动匹配
            if let matched = allContainers.first(where: { $0.serviceType == type }) {
                setContainerName(for: type, name: matched.name)
            }
        }
        _ = settings // silence warning
    }

    private func containerName(for type: ServiceType) -> String {
        switch type {
        case .astrbot: return ""
        case .napcat: return AppSettings.shared.napcatContainer
        case .shipyard: return AppSettings.shared.shipyardContainer
        }
    }

    private func setContainerName(for type: ServiceType, name: String) {
        switch type {
        case .napcat: AppSettings.shared.napcatContainer = name
        case .shipyard: AppSettings.shared.shipyardContainer = name
        case .astrbot: break
        }
    }

    /// 刷新所有服务状态
    func refreshAllStatuses() async {
        await refreshStatus(.astrbot)
        await refreshStatus(.napcat)
        await refreshStatus(.shipyard)
    }

    /// 刷新单个服务状态
    func refreshStatus(_ type: ServiceType) async {
        switch type {
        case .astrbot:
            let running = astrBotController.isRunning
            var svc = services[type] ?? Service(type: type)
            let oldStatus = svc.status
            svc.status = running ? .running : .stopped
            svc.pid = astrBotController.pid
            // Fallback: 如果运行中但 webURL 没解析到（外部启动 / 日志未匹配），用 settings 端口
            if running {
                ensureWebURLForAstrBot(service: &svc)
            } else if oldStatus == .running && !running {
                // 刚停止：清空旧 URL（token 可能失效）
                svc.webURL = nil
            }
            // 只在变化时写入
            let changed: Bool
            if let old = self.services[type] {
                changed = old.status != svc.status || old.pid != svc.pid || old.webURL != svc.webURL
            } else {
                changed = true
            }
            if changed {
                self.services[type] = svc
            }
        case .napcat, .shipyard:
            let containerName = self.containerName(for: type)
            var svc = services[type] ?? Service(type: type)
            let oldStatus = svc.status
            if containerName.isEmpty {
                svc.status = .unknown
                svc.containerName = nil
            } else if let container = allContainers.first(where: { $0.name == containerName }) {
                svc.status = container.isRunning ? .running : .stopped
                svc.containerName = container.name
                svc.image = container.image
                svc.ports = parsePorts(container.ports)
                // Fallback: 运行中但 webURL 没解析到，从 compose 取端口
                if container.isRunning {
                    ensureWebURLFromCompose(service: &svc, type: type)
                }
            } else {
                svc.status = .unknown
                svc.containerName = containerName
            }
            // 刚停止：清空旧 URL
            if oldStatus == .running && svc.status != .running {
                svc.webURL = nil
            }
            // 只在有变化时写入（避免每次 poll 触发 SwiftUI 重渲）
            let changed: Bool
            if let old = self.services[type] {
                changed = old.status != svc.status
                    || old.containerName != svc.containerName
                    || old.image != svc.image
                    || old.ports != svc.ports
                    || old.webURL != svc.webURL
                    || old.pid != svc.pid
            } else {
                changed = true
            }
            if changed {
                self.services[type] = svc
            }
        }
    }

    /// AstrBot WebUI URL fallback（用 settings 端口，不用 compose）
    private func ensureWebURLForAstrBot(service: inout Service) {
        guard service.webURL == nil else { return }
        let port = AppSettings.shared.astrBotWebPort
        if port > 0, let url = URL(string: "http://localhost:\(port)") {
            service.webURL = url
        }
    }

    /// Shipyard WebUI URL fallback（从 compose 解析，因为 Shipyard 日志不输出 webui 端口）
    /// 注意：NapCat **不**用此 fallback（必须从日志取 token，没有 token 就禁用按钮）
    private func ensureWebURLFromCompose(service: inout Service, type: ServiceType) {
        // NapCat 跳过：token 必须从日志拿
        if type == .napcat { return }
        guard service.webURL == nil else { return }
        guard let containerName = service.containerName else { return }

        let serviceName: String
        let defaultPort: Int
        switch type {
        case .shipyard:
            serviceName = "shipyard"
            defaultPort = 8157
        case .napcat, .astrbot:
            return
        }

        // 用缓存（避免每次 refreshStatus 都 docker inspect）
        if let composePath = cachedComposePath(forContainer: containerName) {
            let cacheKey = "\(composePath)|\(serviceName)"
            let ports: [ServicePortInfo]
            if let cached = composePortCache[cacheKey] {
                ports = cached
            } else {
                ports = DockerComposePortParser.ports(
                    fromComposePath: composePath,
                    serviceName: serviceName
                )
                composePortCache[cacheKey] = ports
            }
            // Shipyard: 最后一个 (8157 dashboard)
            let port = ports.last?.hostPort
            if let p = port, p > 0 {
                service.webURL = URL(string: "http://localhost:\(p)")
                return
            }
        }
        // 兜底硬编码
        service.webURL = URL(string: "http://localhost:\(defaultPort)")
    }

    // MARK: - 启停

    func startService(_ type: ServiceType, force: Bool = false) async {
        guard let svc = services[type] else { return }
        if !force, !svc.status.canStart { return }
        services[type]?.status = .starting
        startedByUs.insert(type)

        do {
            switch type {
            case .astrbot:
                try await astrBotController.start { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(level: LogLevel.detect(from: line), source: .astrbot, content: line)
                    }
                }
            case .napcat, .shipyard:
                let name = containerName(for: type)
                if name.isEmpty {
                    throw NSError(domain: "AppState", code: 100, userInfo: [NSLocalizedDescriptionKey: "未配置容器，请先在设置中指定容器"])
                }
                try await ContainerController.start(name: name)
            }
            await refreshContainerList()
            await refreshStatus(type)
            NotificationManager.shared.send(title: "服务启动", body: "\(type.displayName) 已启动")
        } catch {
            var failedSvc = svc
            failedSvc.status = .error
            failedSvc.lastError = error.localizedDescription
            services[type] = failedSvc
            lastError = "\(type.displayName) 启动失败：\(error.localizedDescription)"
            NotificationManager.shared.send(title: "启动失败", body: "\(type.displayName) 启动失败：\(error.localizedDescription)")
        }
    }

    func stopService(_ type: ServiceType, force: Bool = false) async {
        guard let svc = services[type] else { return }
        if !force, !svc.status.canStop { return }
        services[type]?.status = .stopping
        startedByUs.remove(type)

        do {
            switch type {
            case .astrbot:
                await astrBotController.stop()
            case .napcat, .shipyard:
                let name = containerName(for: type)
                if name.isEmpty {
                    throw NSError(domain: "AppState", code: 101, userInfo: [NSLocalizedDescriptionKey: "未配置容器"])
                }
                try await ContainerController.stop(name: name)
            }
            await refreshContainerList()
            await refreshStatus(type)
            NotificationManager.shared.send(title: "服务停止", body: "\(type.displayName) 已停止")
        } catch {
            var failedSvc = svc
            failedSvc.status = .error
            failedSvc.lastError = error.localizedDescription
            services[type] = failedSvc
            lastError = "\(type.displayName) 停止失败：\(error.localizedDescription)"
        }
    }

    func restartService(_ type: ServiceType) async {
        // 重启是显式重置操作：跳过 canStop / canStart 守卫
        // 资源释放靠 processManager.stop() 的 waitpid 等待保证，不需要 sleep
        await stopService(type, force: true)
        await startService(type, force: true)
    }

    func startAll() async {
        // 启动顺序：AstrBot → NapCat → Shipyard
        // （docker start 本身是并行的，但顺序声明可让 UI 启动状态稳定）
        for type in [ServiceType.astrbot, .napcat, .shipyard] {
            await startService(type, force: true)
        }
    }

    func stopAll() async {
        for type in [ServiceType.napcat, .shipyard, .astrbot] {
            await stopService(type, force: true)
        }
    }

    /// 程序退出时清理
    /// 注意：AstrBot 是 daemon 化的，app 退出时不应该终止它
    /// 这里只清理 Docker 容器（如果是我们启动的）
    func cleanupOnExit() {
        for type in startedByUs {
            // AstrBot 跳过：daemon 化，app 关闭不影响 AstrBot
            if type == .astrbot { continue }
            // Docker 容器继续清理（如果是我们启动的）
            if type == .napcat || type == .shipyard {
                let name = containerName(for: type)
                if !name.isEmpty {
                    Task.detached {
                        try? await ContainerController.stop(name: name)
                    }
                }
            }
        }
    }

    // MARK: - 容器创建（兜底）

    /// 从手动 compose 路径创建容器
    func createContainerFromCompose(_ type: ServiceType) async {
        let composePaths = AppSettings.shared.manualComposePaths
        guard !composePaths.isEmpty else {
            lastError = "请先在设置中添加 compose 文件路径"
            return
        }
        // 找包含对应服务名的 compose
        for path in composePaths {
            let expanded = (path as NSString).expandingTildeInPath
            if let content = try? String(contentsOfFile: expanded, encoding: .utf8),
               content.lowercased().contains(type.rawValue) {
                do {
                    try await ContainerController.composeUp(composePath: path)
                    await refreshContainerList()
                    await autoMatchContainers()
                    await refreshStatus(type)
                    return
                } catch {
                    lastError = "创建失败：\(error.localizedDescription)"
                    return
                }
            }
        }
        lastError = "未找到包含 \(type.displayName) 的 compose 文件"
    }

    // MARK: - 轮询

    private func startPolling() {
        pollTimer?.invalidate()
        let interval = TimeInterval(max(1, AppSettings.shared.pollingInterval))
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                await self.refreshContainerList()
                await self.refreshAllStatuses()
            }
        }
    }

    func restartPolling() {
        startPolling()
    }

    // MARK: - 打开 WebUI / 数据目录

    func openWebUI(_ type: ServiceType) {
        // 1. 优先用解析到的 URL（含 token，NapCat）
        if let url = services[type]?.webURL {
            NSWorkspace.shared.open(url)
            return
        }
        // 2. Fallback: 从 docker compose 文件获取端口
        if let url = composeFallbackURL(for: type) {
            NSWorkspace.shared.open(url)
            return
        }
        // 3. Last resort: settings 端口（仅 AstrBot）
        if type == .astrbot {
            let port = AppSettings.shared.astrBotWebPort
            if let url = URL(string: "http://localhost:\(port)") {
                NSWorkspace.shared.open(url)
                return
            }
        }
        lastError = "\(type.displayName) 没有可用的 Web UI URL"
    }

    /// 从 docker compose 文件获取 WebUI URL（fallback）
    private func composeFallbackURL(for type: ServiceType) -> URL? {
        let settings = AppSettings.shared
        let containerName: String
        let serviceName: String
        let defaultPort: Int
        switch type {
        case .astrbot:
            return nil
        case .napcat:
            containerName = settings.napcatContainer
            serviceName = "napcat"
            defaultPort = 6099
        case .shipyard:
            containerName = settings.shipyardContainer
            serviceName = "shipyard"
            defaultPort = 8157
        }

        guard !containerName.isEmpty else { return nil }

        // 1. 尝试从 compose 文件解析
        if let composePath = findComposePath(forContainer: containerName) {
            let ports = DockerComposePortParser.ports(
                fromComposePath: composePath,
                serviceName: serviceName
            )
            // NapCat 取第一个（webui 6099），Shipyard 取最后一个（dashboard 8157）
            let webuiPort: Int? = (type == .napcat) ? ports.first?.hostPort : ports.last?.hostPort
            if let port = webuiPort, port > 0 {
                AppLog.info("WebUI fallback from compose: \(containerName) -> port \(port)")
                return URL(string: "http://localhost:\(port)")
            }
        }

        // 2. 兜底：硬编码默认端口
        return URL(string: "http://localhost:\(defaultPort)")
    }

    /// 查找容器的 compose 文件路径
    private func findComposePath(forContainer containerName: String) -> String? {
        // 1. 尝试 docker inspect
        let result = ShellExecutor.runSync("/usr/local/bin/docker", arguments: [
            "inspect", "--format", "{{ index .Config.Labels \"com.docker.compose.project.config_files\" }}", containerName
        ])
        if result.success, !result.stdout.isEmpty {
            let paths = result.stdout.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if let first = paths.first, FileManager.default.fileExists(atPath: first) {
                return first
            }
        }

        // 2. 退回 manualComposePaths
        return AppSettings.shared.manualComposePaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    func openDataDirectory() {
        let path = (AppSettings.shared.dataDirectory as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 工具

    private func parsePorts(_ portsString: String) -> [String] {
        guard !portsString.isEmpty else { return [] }
        return portsString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// 添加日志到 LogWatcher
    func appendLog(level: LogLevel, source: LogSource, content: String) {
        logWatcher.lines.append(.init(timestamp: Date(), level: level, source: source, content: content))
        if logWatcher.lines.count > 5000 {
            logWatcher.lines.removeFirst(logWatcher.lines.count - 5000)
        }
    }

    /// 当前选中的服务有多少运行中
    var runningCount: Int {
        services.values.filter { $0.status == .running }.count
    }

    /// 总服务数
    var totalCount: Int { ServiceType.allCases.count }
}
