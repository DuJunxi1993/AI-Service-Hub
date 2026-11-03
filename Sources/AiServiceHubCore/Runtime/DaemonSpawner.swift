import Foundation
import Darwin

/// 子进程启动器
///
/// 通过 `posix_spawn` 启动子进程。`detached` 为 true 时加上
/// `POSIX_SPAWN_SETSID`，让子进程脱离本进程所在的会话与进程组：
/// - 本程序退出不影响子进程
/// - 子进程被 launchd 接管
/// - 本程序仍可通过 PID 主动终止它
///
/// **注意**：不要与 `POSIX_SPAWN_SETPGROUP` 组合使用 —— macOS 会返回 EPERM。
public enum DaemonSpawner {
    /// 启动子进程
    /// - Parameters:
    ///   - executable: 可执行文件绝对路径
    ///   - arguments: 参数列表
    ///   - environment: 额外环境变量（与当前进程环境合并）
    ///   - workingDirectory: 工作目录（nil 表示继承）
    ///   - detached: 是否 daemon 化
    /// - Returns: 成功返回子进程 PID
    @discardableResult
    public static func spawn(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        detached: Bool = true
    ) -> pid_t? {
        var attrs: posix_spawnattr_t?
        guard posix_spawnattr_init(&attrs) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attrs) }

        if detached {
            posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID))
        }

        var fileActions: posix_spawn_file_actions_t?
        var fileActionsPtr: UnsafePointer<posix_spawn_file_actions_t?>?
        if let cwd = workingDirectory, !cwd.isEmpty {
            posix_spawn_file_actions_init(&fileActions)
            if posix_spawn_file_actions_addchdir(&fileActions, cwd) != 0 {
                AppLog.error("posix_spawn_file_actions_addchdir failed for \(cwd)")
                return nil
            }
            fileActionsPtr = withUnsafePointer(to: &fileActions) { $0 }
        }
        defer {
            if fileActions != nil {
                posix_spawn_file_actions_destroy(&fileActions)
            }
        }

        let allArgs = [executable] + arguments
        let argv: [UnsafeMutablePointer<CChar>?] = allArgs.map { strdup($0) } + [nil]
        defer { argv.forEach { if let p = $0 { free(p) } } }

        var envDict = ProcessInfo.processInfo.environment
        if let environment {
            for (key, value) in environment { envDict[key] = value }
        }
        let envp: [UnsafeMutablePointer<CChar>?] = envDict.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { if let p = $0 { free(p) } } }

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

        AppLog.info("Spawned process: pid=\(pid) executable=\(executable) detached=\(detached) cwd=\(workingDirectory ?? "inherit")")
        return pid
    }
}
