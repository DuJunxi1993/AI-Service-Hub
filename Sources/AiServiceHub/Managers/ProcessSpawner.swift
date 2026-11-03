import Foundation
import Darwin

/// 进程守护启动器
///
/// 使用 posix_spawn 启动子进程并通过 POSIX_SPAWN_SETSID | POSIX_SPAWN_SETPGROUP
/// 让子进程脱离父进程的进程组与会话，从而实现 daemon 化：
/// - 父进程退出不影响子进程
/// - 子进程被 launchd 接管
/// - 父进程可通过 PID 主动 kill 子进程
enum ProcessSpawner {
    /// Spawn 一个 daemon 化的子进程
    /// - Parameters:
    ///   - executable: 可执行文件绝对路径
    ///   - arguments: 参数列表
    ///   - environment: 额外环境变量（会与当前进程环境合并）
    ///   - workingDirectory: 工作目录（可选，nil 则继承父进程）
    /// - Returns: 成功返回子进程 PID（可用于后续管理）
    @discardableResult
    static func spawnDaemon(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil
    ) -> pid_t? {
        // 1. 创建 posix_spawn 属性
        var attrs: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&attrs) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attrs) }

        // 2. 设置 flags 让子进程脱离父进程
        //    注意：POSIX_SPAWN_SETSID 已经会创建新的会话和进程组
        //    不能与 POSIX_SPAWN_SETPGROUP 同时使用（macOS 会返回 EPERM）
        let flags: Int16 = Int16(POSIX_SPAWN_SETSID)
        posix_spawnattr_setflags(&attrs, flags)

        // 3. file_actions（chdir）
        var fileActions: posix_spawn_file_actions_t? = nil
        var fileActionsPtr: UnsafePointer<posix_spawn_file_actions_t?>? = nil
        if let cwd = workingDirectory, !cwd.isEmpty {
            posix_spawn_file_actions_init(&fileActions)
            if posix_spawn_file_actions_addchdir_np(&fileActions, cwd) != 0 {
                AppLog.error("posix_spawn_file_actions_addchdir_np failed")
                return nil
            }
            fileActionsPtr = withUnsafePointer(to: &fileActions) { $0 }
        }
        defer {
            if fileActions != nil {
                posix_spawn_file_actions_destroy(&fileActions)
            }
        }

        // 4. 准备 argv
        let allArgs = [executable] + arguments
        let argv: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) } + [nil]
        defer { argv.forEach { if let p = $0 { free(p) } } }

        // 5. 准备 envp
        var envDict = ProcessInfo.processInfo.environment
        if let environment {
            for (k, v) in environment { envDict[k] = v }
        }
        let envp: [UnsafeMutablePointer<CChar>?] = envDict.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { if let p = $0 { free(p) } } }

        // 6. posix_spawn
        var pid: pid_t = 0
        let result = posix_spawn(
            &pid,
            executable,
            fileActionsPtr,
            &attrs,
            argv,
            envp
        )

        if result != 0 {
            AppLog.error("posix_spawn failed: \(String(cString: strerror(result)))")
            return nil
        }

        AppLog.info("Spawned daemon process: pid=\(pid) executable=\(executable) cwd=\(workingDirectory ?? "inherit")")
        return pid
    }
}
