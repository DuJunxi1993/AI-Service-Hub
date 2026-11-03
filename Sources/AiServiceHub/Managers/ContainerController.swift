import Foundation

/// Docker 容器控制器（直接管理现成容器）
@MainActor
final class ContainerController {
    /// 容器信息
    struct Container: Identifiable, Hashable {
        let id: String          // container ID
        let name: String
        let image: String
        let state: String       // running / exited / paused / ...
        let status: String      // "Up 2 days" / "Exited (0) 3 hours ago"
        let ports: String       // "0.0.0.0:8156->8156/tcp"
        let createdAt: String

        var isRunning: Bool { state.lowercased() == "running" }

        /// 根据 image 关键字推断服务类型
        var serviceType: ServiceType? {
            ServiceType.from(image: image) ?? ServiceType.from(containerName: name)
        }
    }

    /// 列出所有容器（包括停止的）
    static func listAll() async throws -> [Container] {
        guard let docker = ShellExecutor.which("docker") else {
            throw error("未找到 docker 命令")
        }
        let result = try await ShellExecutor.run(
            docker,
            arguments: ["ps", "-a", "--format", "json"]
        )

        guard result.success else {
            AppLog.warn("docker ps failed: \(result.stderr)")
            return []
        }

        let lines = result.stdout.split(separator: "\n")
        return lines.compactMap { line -> Container? in
            guard let lineData = String(line).data(using: .utf8) else { return nil }
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return nil }
            return parseContainer(obj)
        }
    }

    /// 启动容器
    static func start(name: String) async throws {
        guard let docker = ShellExecutor.which("docker") else {
            throw error("未找到 docker 命令")
        }
        let result = try await ShellExecutor.run(
            docker,
            arguments: ["start", name]
        )
        if !result.success {
            throw error("启动容器失败：\n\(result.stderr)")
        }
        AppLog.info("Container started: \(name)")
    }

    /// 停止容器
    static func stop(name: String) async throws {
        guard let docker = ShellExecutor.which("docker") else {
            throw error("未找到 docker 命令")
        }
        let result = try await ShellExecutor.run(
            docker,
            arguments: ["stop", name]
        )
        if !result.success {
            throw error("停止容器失败：\n\(result.stderr)")
        }
        AppLog.info("Container stopped: \(name)")
    }

    /// 重启容器
    static func restart(name: String) async throws {
        guard let docker = ShellExecutor.which("docker") else {
            throw error("未找到 docker 命令")
        }
        let result = try await ShellExecutor.run(
            docker,
            arguments: ["restart", name]
        )
        if !result.success {
            throw error("重启容器失败：\n\(result.stderr)")
        }
        AppLog.info("Container restarted: \(name)")
    }

    /// 启动容器日志流
    static func logs(containerName: String, tail: Int = 500) -> Process? {
        guard let docker = ShellExecutor.which("docker") else { return nil }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: docker)
        proc.arguments = ["logs", "--tail", "\(tail)", "-f", containerName]
        proc.standardOutput = pipe
        proc.standardError = pipe
        return proc
    }

    /// 检查 docker daemon 是否可用（5s 缓存）
    static func isDockerAvailable() -> Bool {
        let ttl: TimeInterval = 5
        if let cached = ShellExecutor.dockerAvailableCache,
           Date().timeIntervalSince(cached.timestamp) < ttl {
            return cached.available
        }
        guard let docker = ShellExecutor.which("docker") else {
            ShellExecutor.dockerAvailableCache = (false, Date())
            return false
        }
        let result = ShellExecutor.runSync(docker, arguments: ["info"])
        let available = result.success
        ShellExecutor.dockerAvailableCache = (available, Date())
        return available
    }

    /// 从 compose 文件创建容器（兜底用）
    static func composeUp(composePath: String) async throws {
        guard let docker = ShellExecutor.which("docker") else {
            throw error("未找到 docker 命令")
        }
        let expandedPath = (composePath as NSString).expandingTildeInPath
        guard ShellExecutor.exists(expandedPath) else {
            throw error("compose 文件不存在: \(expandedPath)")
        }
        let dir = (expandedPath as NSString).deletingLastPathComponent

        let result = try await ShellExecutor.run(
            docker,
            arguments: ["compose", "-f", expandedPath, "up", "-d"],
            workingDirectory: dir
        )
        if !result.success {
            throw error("docker compose up 失败：\n\(result.stderr)")
        }
        AppLog.info("docker compose up: \(expandedPath)")
    }

    // MARK: - 私有

    private static func error(_ message: String) -> NSError {
        NSError(domain: "ContainerController", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func parseContainer(_ obj: [String: Any]) -> Container? {
        let id = obj["ID"] as? String ?? ""
        guard !id.isEmpty else { return nil }
        let name = obj["Names"] as? String ?? obj["Name"] as? String ?? id
        let image = obj["Image"] as? String ?? ""
        let state = obj["State"] as? String ?? ""
        let status = obj["Status"] as? String ?? state
        let ports = obj["Ports"] as? String ?? ""
        let createdAt = obj["CreatedAt"] as? String ?? ""
        return Container(
            id: id,
            name: name,
            image: image,
            state: state,
            status: status,
            ports: ports,
            createdAt: createdAt
        )
    }
}
