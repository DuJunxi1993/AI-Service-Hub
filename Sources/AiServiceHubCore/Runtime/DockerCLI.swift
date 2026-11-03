import Foundation

/// 一个 Docker 容器
public struct DockerContainer: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let image: String
    /// running / exited / paused / ...
    public let state: String
    /// "Up 2 days" / "Exited (0) 3 hours ago"
    public let status: String
    /// "0.0.0.0:8156->8156/tcp"
    public let ports: String

    public init(id: String, name: String, image: String, state: String, status: String, ports: String) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
    }

    public var isRunning: Bool { state.lowercased() == "running" }
}

/// Docker CLI 的薄封装
public struct DockerCLI: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    /// docker 可执行文件路径
    public func executablePath() -> String? {
        ExecutableLocator.shared.which("docker")
    }

    /// daemon 是否可用
    public func isAvailable() async -> Bool {
        guard let docker = executablePath() else { return false }
        let result = await runner.runIgnoringFailure(docker, arguments: ["info"], timeout: .seconds(10))
        return result.success
    }

    /// 列出所有容器（含已停止的）
    public func listContainers() async throws -> [DockerContainer] {
        guard let docker = executablePath() else {
            throw DockerError.dockerNotFound
        }
        let result = try await runner.run(
            docker,
            arguments: ["ps", "-a", "--format", "json"],
            timeout: .seconds(20)
        )
        guard result.success else {
            throw DockerError.commandFailed("docker ps", result.stderr)
        }
        return Self.parseContainerList(result.stdout)
    }

    /// 启动容器
    public func start(container name: String) async throws {
        try await run(["start", name], action: "启动")
    }

    /// 停止容器
    public func stop(container name: String) async throws {
        try await run(["stop", name], action: "停止")
    }

    /// 重启容器
    public func restart(container name: String) async throws {
        try await run(["restart", name], action: "重启")
    }

    private func run(_ arguments: [String], action: String) async throws {
        guard let docker = executablePath() else {
            throw DockerError.dockerNotFound
        }
        let result = try await runner.run(docker, arguments: arguments, timeout: .seconds(120))
        guard result.success else {
            throw DockerError.commandFailed(action, result.stderr)
        }
    }

    /// 解析 `docker ps --format json` 的逐行 JSON 输出
    static func parseContainerList(_ output: String) -> [DockerContainer] {
        output.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["ID"] as? String, !id.isEmpty else {
                return nil
            }
            return DockerContainer(
                id: id,
                name: object["Names"] as? String ?? object["Name"] as? String ?? id,
                image: object["Image"] as? String ?? "",
                state: object["State"] as? String ?? "",
                status: object["Status"] as? String ?? "",
                ports: object["Ports"] as? String ?? ""
            )
        }
    }
}

/// Docker 相关错误
public enum DockerError: Error, LocalizedError {
    case dockerNotFound
    case commandFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .dockerNotFound:
            return "未找到 docker 命令"
        case .commandFailed(let action, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "docker \(action)失败" : "docker \(action)失败：\(detail)"
        }
    }
}
