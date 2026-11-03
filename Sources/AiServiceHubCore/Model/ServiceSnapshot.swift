import Foundation

/// 服务的运行时快照 —— 探测到的「事实」
///
/// 与 `ServiceDescriptor`（配置）分离：描述符是用户写的，快照是系统观测到的。
public struct ServiceSnapshot: Sendable, Equatable {
    public var descriptorID: UUID
    public var status: ServiceStatus
    public var pid: Int32?
    /// 进程启动时间标识，用于识别 PID 复用
    public var processStartTimeToken: String?
    public var containerName: String?
    public var image: String?
    public var ports: [String]
    /// 监听端口（探测得到）
    public var listeningPorts: [Int]
    /// 解析到的 WebUI 地址（可能含 token）
    public var webURL: URL?
    /// 最近一次错误
    public var lastError: String?
    /// 各探测项的结果
    public var probeResults: [ProbeResult]
    /// 该进程是否由本程序启动（false 表示外部启动）
    public var startedByUs: Bool
    /// 最近一次状态变化时间
    public var updatedAt: Date

    public init(
        descriptorID: UUID,
        status: ServiceStatus = .unknown,
        pid: Int32? = nil,
        processStartTimeToken: String? = nil,
        containerName: String? = nil,
        image: String? = nil,
        ports: [String] = [],
        listeningPorts: [Int] = [],
        webURL: URL? = nil,
        lastError: String? = nil,
        probeResults: [ProbeResult] = [],
        startedByUs: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.descriptorID = descriptorID
        self.status = status
        self.pid = pid
        self.processStartTimeToken = processStartTimeToken
        self.containerName = containerName
        self.image = image
        self.ports = ports
        self.listeningPorts = listeningPorts
        self.webURL = webURL
        self.lastError = lastError
        self.probeResults = probeResults
        self.startedByUs = startedByUs
        self.updatedAt = updatedAt
    }

    /// 状态是否有实质变化（用于避免无谓的界面刷新）
    public func hasSameRuntimeState(as other: ServiceSnapshot) -> Bool {
        status == other.status
            && pid == other.pid
            && processStartTimeToken == other.processStartTimeToken
            && containerName == other.containerName
            && image == other.image
            && ports == other.ports
            && listeningPorts == other.listeningPorts
            && webURL == other.webURL
            && lastError == other.lastError
            && startedByUs == other.startedByUs
    }
}
