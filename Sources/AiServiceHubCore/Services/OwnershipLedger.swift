import Foundation

/// 进程所有权账本
///
/// 记录本程序启动过哪些进程，用来：
/// 1. 判定某个 pid 是否还是「本程序启动的那个」（pid 会被系统复用）
/// 2. launcher 被强杀 / 崩溃后回收 `detached == false` 的孤儿进程
public struct OwnershipLedger: Sendable {
    private let driver: ProcessDriver

    public init(driver: ProcessDriver = ProcessDriver()) {
        self.driver = driver
    }

    /// 某个服务当前持有的进程记录
    public func record(for serviceID: UUID, in config: AppConfig) -> OwnedProcessRecord? {
        config.ownedProcesses.first { $0.serviceID == serviceID }
    }

    /// 写入 / 更新记录
    public func upsert(_ record: OwnedProcessRecord, in config: inout AppConfig) {
        if let index = config.ownedProcesses.firstIndex(where: { $0.serviceID == record.serviceID }) {
            config.ownedProcesses[index] = record
        } else {
            config.ownedProcesses.append(record)
        }
    }

    /// 移除某个服务的记录
    public func remove(serviceID: UUID, from config: inout AppConfig) {
        config.ownedProcesses.removeAll { $0.serviceID == serviceID }
    }

    /// 移除某个 pid 的记录
    public func remove(pid: Int32, from config: inout AppConfig) {
        config.ownedProcesses.removeAll { $0.pid == pid }
    }

    /// 启动时回收孤儿进程
    ///
    /// - `detached == false`：进程本应随 launcher 一起结束，若还活着说明上次是非正常退出，终止它。
    /// - `detached == true`：daemon 化语义，进程本就该继续存活，只把它从账本里摘掉。
    ///
    /// 无论哪种情况，账本在回收后都会清空：本次会话还没启动过任何东西。
    ///
    /// - Returns: 被终止的 pid 列表
    @discardableResult
    public func reclaimOrphans(in records: inout [OwnedProcessRecord]) async -> [Int32] {
        var terminated: [Int32] = []
        var remaining: [OwnedProcessRecord] = []

        for record in records {
            let alive = ProcessInspector.matchesIdentity(
                pid: record.pid,
                startTimeToken: record.startTimeToken
            )
            if !alive {
                // 进程已经不在了，账本条目直接丢弃
                continue
            }
            if record.detached {
                // daemon 化：保留进程，但从账本摘除
                AppLog.info("保留 daemon 化进程 \(record.pid)（服务 \(record.serviceID.uuidString.prefix(8))）")
                continue
            }
            // 应当随 app 退出却还活着 —— 回收
            AppLog.warn("回收孤儿进程 \(record.pid)")
            await driver.stop(record: record)
            terminated.append(record.pid)
        }

        records = remaining
        return terminated
    }
}
