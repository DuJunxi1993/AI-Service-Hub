import Foundation

/// 持有子进程时的所有权设置
public struct ProcessOwnership: Codable, Sendable, Hashable {
    /// 是否 daemon 化（脱离会话与进程组）
    ///
    /// - `true`：launcher 退出后进程继续存活（AstrBot 的既有行为）
    /// - `false`：子进程留在 launcher 进程组内，随 launcher 一起结束
    public var detached: Bool

    /// launcher 退出时是否主动终止该进程
    public var stopOnAppQuit: Bool

    public init(detached: Bool, stopOnAppQuit: Bool) {
        self.detached = detached
        self.stopOnAppQuit = stopOnAppQuit
    }

    public static let daemon = ProcessOwnership(detached: true, stopOnAppQuit: false)
    public static let tiedToApp = ProcessOwnership(detached: false, stopOnAppQuit: true)
}

/// 可管理进程的配置
public struct ProcessSpec: Codable, Sendable, Hashable {
    /// 可执行文件路径（~ 与环境变量会被展开）
    public var executable: String
    /// 参数列表
    public var arguments: [String]
    /// 工作目录
    public var workingDirectory: String?
    /// 额外环境变量
    public var environment: [String: String]
    /// 是否经由 `/bin/sh -c` 执行
    ///
    /// `false` 时命令被拆成 argv 直接 exec，`&&`、`|` 等 shell 语法**不生效**。
    public var shellMode: Bool
    /// 所有权设置
    public var ownership: ProcessOwnership
    /// 存活检测用的命令行匹配模式
    public var processMatch: [String]

    public init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        shellMode: Bool = false,
        ownership: ProcessOwnership = .daemon,
        processMatch: [String] = []
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.shellMode = shellMode
        self.ownership = ownership
        self.processMatch = processMatch
    }
}

/// 委托给 Docker 容器的配置
public struct ContainerSpec: Codable, Sendable, Hashable {
    /// 容器名
    public var containerName: String
    /// compose 文件路径（可选，用于解析端口）
    public var composePath: String?
    /// launcher 退出时是否停止该容器
    public var stopOnAppQuit: Bool

    public init(containerName: String, composePath: String? = nil, stopOnAppQuit: Bool = true) {
        self.containerName = containerName
        self.composePath = composePath
        self.stopOnAppQuit = stopOnAppQuit
    }
}

/// 可管理服务的具体配置
public enum ManagedSpec: Codable, Sendable, Hashable {
    case process(ProcessSpec)
    case container(ContainerSpec)

    public var driver: ManagedDriver {
        switch self {
        case .process: return .process
        case .container: return .container
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case driver
        case process
        case container
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let driver = try container.decode(ManagedDriver.self, forKey: .driver)
        switch driver {
        case .process:
            self = .process(try container.decode(ProcessSpec.self, forKey: .process))
        case .container:
            self = .container(try container.decode(ContainerSpec.self, forKey: .container))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(driver, forKey: .driver)
        switch self {
        case .process(let spec):
            try container.encode(spec, forKey: .process)
        case .container(let spec):
            try container.encode(spec, forKey: .container)
        }
    }
}
