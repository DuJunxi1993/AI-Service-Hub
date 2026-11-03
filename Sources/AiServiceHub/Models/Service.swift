import Foundation
import SwiftUI

/// 单个服务的运行时数据
struct Service: Identifiable, Hashable {
    let id: UUID
    let type: ServiceType
    var status: ServiceStatus
    var containerName: String?       // docker 容器名，如 napcat-napcat-1
    var image: String?               // 镜像名，如 mlikiowa/napcat-docker:v4.15.0
    var pid: Int32?                  // 进程 PID（仅 AstrBot）
    var port: Int?                   // Web 端口（deprecated，用 webURL 替代）
    var webURL: URL?                 // 解析到的完整 WebUI URL（含 token）
    var uptime: Date?                // 启动时间
    var lastError: String?           // 最近错误
    var ports: [String]              // 已暴露端口列表

    init(
        id: UUID = UUID(),
        type: ServiceType,
        status: ServiceStatus = .unknown,
        containerName: String? = nil,
        image: String? = nil,
        pid: Int32? = nil,
        port: Int? = nil,
        webURL: URL? = nil,
        uptime: Date? = nil,
        lastError: String? = nil,
        ports: [String] = []
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.containerName = containerName
        self.image = image
        self.pid = pid
        self.port = port
        self.webURL = webURL
        self.uptime = uptime
        self.lastError = lastError
        self.ports = ports
    }

    /// WebUI 端口（兼容旧逻辑）
    /// 优先用 webURL（包含 token），否则用 port
    var webPort: Int? {
        if let url = webURL { return url.port }
        return port
    }
}
